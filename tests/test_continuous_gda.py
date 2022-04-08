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

INITIAL_PRICE = 1000
DECAY_CONSTANT = 5
EMISSION_RATE = 10


@pytest.fixture(scope="module")
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope="module")
async def contract_factory():
    # Deploy the contracts
    starknet = await Starknet.empty()
    account1 = await starknet.deploy(
        "openzeppelin/account/Account.cairo",
        constructor_calldata=[signer.public_key],
    )
    contract = await starknet.deploy(
        "contracts/continuousGDA.cairo",
        constructor_calldata=[
            str_to_felt("Token"),  # name
            str_to_felt("TKN"),  # ticker
            account1.contract_address,  # owner
            INITIAL_PRICE,
            EMISSION_RATE,
            DECAY_CONSTANT,
        ],
    )
    account2 = await starknet.deploy(
        "openzeppelin/account/Account.cairo",
        constructor_calldata=[signer.public_key],
    )
    # ERC20 type accepted as payment
    erc20 = await starknet.deploy(
        "openzeppelin/token/erc20/ERC20_Mintable.cairo",
        constructor_calldata=[
            str_to_felt("Mintable Token"),
            str_to_felt("MTKN"),
            18,
            *to_uint(100000),
            account2.contract_address,
            account2.contract_address,
        ],
    )

    # Approve the tokens for the auction contract
    await signer.send_transaction(
        account=account2,
        to=erc20.contract_address,
        selector_name="approve",
        calldata=[contract.contract_address, *to_uint(2002)],
    )

    return starknet, contract, account1, account2, erc20


@pytest.mark.asyncio
async def test_initial_price(contract_factory):
    """Initial price should be price scale"""
    starknet, contract, account1, account2, erc20 = contract_factory

    observed = await contract.purchase_price(1).call()
    assert assertApproxEqual(INITIAL_PRICE, observed.result[0][0], 1)


@pytest.mark.asyncio
async def test_insufficient_payment(contract_factory):
    starknet, contract, account1, account2, erc20 = contract_factory
    # TODO: Warp 10 blocks ahead = 10 tokens available for sale

    observed = await contract.purchase_price(5).call()


    with pytest.raises(StarkException):
        await signer.send_transaction(
            account=account2,
            to=contract.contract_address,
            selector_name="purchaseTokens",
            calldata=[
                5,
                account2.contract_address,
                *to_uint(observed.result[0][0] - 1),
            ],
        )

@pytest.mark.asyncio
async def test_insufficient_emissions(contract_factory):
    starknet, contract, account1, account2, erc20 = contract_factory
    # TODO: Warp 10 blocks ahead = 10 tokens available for sale

    observed = await contract.purchase_price(11).call()

    # Attempt to purchaswe 11 tokens
    with pytest.raises(StarkException):
        await signer.send_transaction(
            account=account2,
            to=contract.contract_address,
            selector_name="purchaseTokens",
            calldata=[
                11,
                account2.contract_address,
                *to_uint(observed.result[0][0] - 1),
            ],
        )


@pytest.mark.asyncio
async def test_mint_correctly(contract_factory):
    starknet, contract, account1, account2, erc20 = contract_factory
    # TODO : Warp 10 blocks ahead = 10 tokens available for sale


    # Checks balance is null
    balance = await contract.balanceOf(account2.contract_address).call()
    assert balance.result == ((0, 0),)

    price = await contract.purchase_price(5).call()
    assert price.result[0][0] > 0

    await signer.send_transaction(
        account=account2,
        to=contract.contract_address,
        selector_name="purchaseTokens",
        calldata=[
            5,
            account2.contract_address,
            *to_uint(price.result[0][0]),
        ],
    )

    # Checks balance is updated
    balance_new = await contract.balanceOf(account2.contract_address).call()
    assert balance_new.result == ((5, 0),)


# @pytest.mark.asyncio
# async def test_refund(contract_factory):
#     starknet, contract, account1, account2, erc20 = contract_factory

#     price = await contract.purchase_price(1).call()
#     await signer.send_transaction(
#         account=account2,
#         to=contract.contract_address,
#         selector_name="purchaseTokens",
#         calldata=[
#             1,
#             account2.contract_address,
#             *to_uint(2002),
#         ],
#     )

#     observed = await erc20.balanceOf(account2.contract_address).call()
#     assert observed.result == price.result


def assertApproxEqual(expected, actual, tolerance):
    print(expected, actual, tolerance)
    leftBound = (expected * (1000 - tolerance)) / 1000
    rightBound = (expected * (1000 + tolerance)) / 1000
    return leftBound <= actual and actual <= rightBound
