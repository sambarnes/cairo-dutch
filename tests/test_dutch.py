import asyncio

import pytest
import starkware.starknet.testing.objects
from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException

from tests.utils import Signer, str_to_felt, to_uint, uint


FALSE, TRUE = 0, 1
signer = Signer(123456789987654321)

NONEXISTENT_TOKEN = to_uint(999)
# random token IDs
TOKENS = [to_uint(5042), to_uint(793)]
# test token
TOKEN = TOKENS[0]

STARTING_PRICE = to_uint(500)


@pytest.fixture(scope="module")
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope="module")
async def contract_factory():
    # Deploy the contracts
    starknet = await Starknet.empty()
    contract = await starknet.deploy("contracts/dutch.cairo")
    account1 = await starknet.deploy(
        "openzeppelin/account/Account.cairo",
        constructor_calldata=[signer.public_key],
    )
    account2 = await starknet.deploy(
        "openzeppelin/account/Account.cairo",
        constructor_calldata=[signer.public_key],
    )
    # NFT type being sold
    erc721 = await starknet.deploy(
        "openzeppelin/token/erc721/ERC721_Mintable_Burnable.cairo",
        constructor_calldata=[
            str_to_felt("Non Fungible Token"),  # name
            str_to_felt("NFT"),                 # ticker
            account1.contract_address           # owner
        ]
    )
    # ERC20 type accepted as payment
    erc20 = await starknet.deploy(
        "openzeppelin/token/erc20/ERC20_Mintable.cairo",
        constructor_calldata=[
            str_to_felt("Mintable Token"),
            str_to_felt("MTKN"),
            18,
            *STARTING_PRICE,
            account2.contract_address,
            account2.contract_address
        ]
    )

    # Mint tokens to account1
    for token in TOKENS:
        await signer.send_transaction(
            account=account1,
            to=erc721.contract_address,
            selector_name="mint",
            calldata=[account1.contract_address, *token]
        )
    
    # Approve the tokens for the auction contract
    await signer.send_transaction(
        account=account1,
        to=erc721.contract_address,
        selector_name="setApprovalForAll",
        calldata=[contract.contract_address, TRUE]
    )
    await signer.send_transaction(
        account=account2,
        to=erc20.contract_address,
        selector_name="approve",
        calldata=[contract.contract_address, *STARTING_PRICE]
    )

    return starknet, contract, account1, account2, erc721, erc20


@pytest.mark.asyncio
async def test_isInitialized(contract_factory):
    """Should be uninitialized by default"""
    starknet, contract, account1, account2, erc721, erc20 = contract_factory

    observed = await contract.isInitialized().call()
    assert observed.result == (FALSE, )


@pytest.mark.asyncio
async def test_initialize_not_owner(contract_factory):
    """Should not intialize auction for token not owned"""
    starknet, contract, account1, account2, erc721, erc20 = contract_factory

    with pytest.raises(StarkException):
        await signer.send_transaction(
            account=account2,  # NOT THE RIGHT ACCOUNT
            to=contract.contract_address,
            selector_name="initialize",
            calldata=[
                erc721.contract_address,  # nftAddress
                *TOKEN,  # tokenId
                erc20.contract_address,  # erc20Address
                *STARTING_PRICE,  # startingPrice
                *uint(1),  # discountRate
                30,  # durationBlocks
            ]
        )

    # Should not be initialized
    observed = await contract.isInitialized().call()
    assert observed.result == (FALSE, )


@pytest.mark.asyncio
async def test_initialize(contract_factory):
    """Should intialize auction if token owned"""
    starknet, contract, account1, account2, erc721, erc20 = contract_factory

    await signer.send_transaction(
        account=account1,
        to=contract.contract_address,
        selector_name="initialize",
        calldata=[
            erc721.contract_address,  # nftAddress
            *TOKEN,  # tokenId
            erc20.contract_address,  # erc20Address
            *STARTING_PRICE,  # startingPrice
            *uint(1),  # discountRate
            30,  # durationBlocks
        ]
    )

    # Should now be initialized
    observed = await contract.isInitialized().call()
    assert observed.result == (TRUE, )


@pytest.mark.asyncio
async def test_buy_as_seller(contract_factory):
    """Should not buy if seller == buyer"""
    starknet, contract, account1, account2, erc721, erc20 = contract_factory

    with pytest.raises(StarkException):
        await signer.send_transaction(
            account=account1,
            to=contract.contract_address,
            selector_name="buy",
            calldata=[*STARTING_PRICE]
        )


@pytest.mark.asyncio
async def test_buy_lowball(contract_factory):
    """Should not buy if bid < price"""
    starknet, contract, account1, account2, erc721, erc20 = contract_factory

    with pytest.raises(StarkException):
        await signer.send_transaction(
            account=account2,
            to=contract.contract_address,
            selector_name="buy",
            calldata=[*uint(499)]
        )


@pytest.mark.asyncio
async def test_buy(contract_factory):
    """Should buy if all conditions met"""
    starknet, contract, account1, account2, erc721, erc20 = contract_factory

    await signer.send_transaction(
        account=account2,
        to=contract.contract_address,
        selector_name="buy",
        calldata=[*STARTING_PRICE]
    )

    # Checks token has new owner
    observed = await erc721.ownerOf(TOKEN).call()
    assert observed.result == (account2.contract_address,)

    # Checks ERC20 balances updated for buyer & seller
    observed = await erc20.balanceOf(account2.contract_address).call()
    assert observed.result == ((0, 0),)
    observed = await erc20.balanceOf(account1.contract_address).call()
    assert observed.result == (STARTING_PRICE,)



@pytest.mark.asyncio
async def test_buy_sold(contract_factory):
    """Should not buy if auction already sold"""
    starknet, contract, account1, account2, erc721, erc20 = contract_factory

    with pytest.raises(StarkException):
        await signer.send_transaction(
            account=account2,
            to=contract.contract_address,
            selector_name="buy",
            calldata=[*STARTING_PRICE]
        )
