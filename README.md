# 🇳🇱 cairo-dutch

A Dutch Auction written in [Cairo](https://cairo-lang.org/docs/) for StarkNet. Ported after studying [a reference implementation](https://solidity-by-example.org/app/multi-sig-wallet/) from solidity-by-example.

A Gradual Dutch Auction has also been added for Starknet. It refers to a new type of Dutch Auction created by [Paradigm Research](https://www.paradigm.xyz/2022/04/gda)

Allows configurable duration, discount rate, & ERC20 token type accepted as payment.

> ⚠️ WARNING: This is not intended for production use. The code has barely been tested, let alone audited.

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

### VSCode DevContainers

This was required (for me, at least) to run on an M1 mac instead of my usual ubuntu box. Using the setup found in [tarrencev/starknet-scaffold](https://github.com/tarrencev/starknet-scaffold) I was able to get it working in VSCode.

> If you are using VSCode, we provide a development container with all required dependencies. When opening VS Code, it should ask you to re-open the project in a container, if it finds the .devcontainer folder. If not, you can open the Command Palette (cmd + shift + p), and run “Remote-Containers: Reopen in Container”.

In the `Cairo LS` shell that gets spawned, run `poetry install`. Then, a `poetry run pytest` should function as if we were on the typical linux setup.
