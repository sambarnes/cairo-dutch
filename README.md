# 🇳🇱 cairo-dutch

A Dutch Auction written in [Cairo](https://cairo-lang.org/docs/) for StarkNet. Ported after studying [a reference implementation](https://solidity-by-example.org/app/multi-sig-wallet/) from solidity-by-example.

A Gradual Dutch Auction has also been added for Starknet. It refers to a new type of Dutch Auction created by [Paradigm Research](https://www.paradigm.xyz/2022/04/gda)

Allows configurable duration, discount rate, & ERC20 token type accepted as payment.

> ⚠️ WARNING: This is not intended for production use. The code has barely been tested, let alone audited.

Basic Dutch Auction:

1. Seller of NFT deploys this contract setting a starting price & ERC20 token type accepted.
2. Auction lasts for a configurable number of blocks (`durationBlocks`).
3. Price decreases over time (`discountRate`).
4. Participants can buy if sending ERC20 value greater than or equal to the current price computed by the contract.
5. Auction ends when a buyer buys the NFT or the deadline is reached.

## Development

```
python3.7 -m venv venv
source venv/bin/activate
python -m pip install cairo-nile
nile install
```

Needs more tests, but basic coverage can be run using the following:

```
(venv) ~/dev/eth/starknet/cairo-dutch$ make test
pytest tests/
================================  test session starts =======================================
platform linux -- Python 3.7.12, pytest-7.0.1, pluggy-1.0.0
rootdir: /home/sam/dev/eth/starknet/cairo-dutch
plugins: asyncio-0.18.2, typeguard-2.13.3, web3-5.28.0
asyncio: mode=legacy
collected 7 items

tests/test_dutch.py .......                                                           [100%]
========================= 7 passed, 3 warnings in 123.53s (0:02:03) =========================
```
