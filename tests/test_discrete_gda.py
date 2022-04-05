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
    contract = await starknet.deploy("contracts/discreteGDA.cairo")
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


