# 🇳🇱 cairo-dutch

A Dutch Auction written in [Cairo](https://cairo-lang.org/docs/) for StarkNet. Ported after studying [a reference implementation](https://solidity-by-example.org/app/multi-sig-wallet/) from solidity-by-example.

> ⚠️ WARNING: This is not intended for production use. The code has barely been tested, let alone audited.

Auction:
1) Seller of NFT deploys this contract setting a starting price for the NFT.
2) Auction lasts for a configurable number of blocks.
3) Price decreases over time.
4) Participants can buy if sending ETH greater than the current price computed by the contract.
5) Auction ends when a buyer buys the NFT or the deadline is reached

> I don't think actually sending ETH is allowed right now, but I've stubbed out where these syscalls would go when thats available


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