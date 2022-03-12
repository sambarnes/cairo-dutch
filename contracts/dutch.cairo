%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import (
    assert_le,
    assert_not_equal,
    split_felt,
)
from starkware.cairo.common.math_cmp import is_not_zero
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_le,
    uint256_mul,
    uint256_sub,
)
from starkware.starknet.common.syscalls import (
    get_block_number,
    get_caller_address,
)

from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from openzeppelin.token.erc721.interfaces.IERC721 import IERC721
from openzeppelin.utils.constants import FALSE, TRUE


#
# Storage (kept as a single global for simplicity)
#


struct Auction:
    member nftAddress : felt
    member tokenId : Uint256
    member seller : felt

    member erc20Address : felt      # Token type accepted
    member startingPrice : Uint256  # Denominated in above token type
    member discountRate : Uint256   # Discount = DiscountRate * (CurrentBlock * StartBlock)
    member startBlock : felt
    member durationBlocks : felt
    member sold : felt
end


@storage_var
func auction() -> (res : Auction):
end


#
# Getters
#


@view
func getAuction{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
    }() -> (
        res : Auction
    ):
    let (res) = auction.read()
    return (res)
end


@view
func isInitialized{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
    }() -> (
        res : felt
    ):
    let (thisAuction) = auction.read()
    let (res) = is_not_zero(thisAuction.startBlock)
    return (res)
end


@view
func getPrice{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
    }() -> (
        res : Uint256
    ):
    alloc_locals
    let (local thisAuction) = auction.read()

    # Discount = DiscountRate * (CurrentBlock - StartBlock)
    let (currentBlock) = get_block_number()
    let blocksElapsed = currentBlock - thisAuction.startBlock
    let (blocksElapsedUint) = felt_to_uint256(blocksElapsed)
    let (discount, carry) = uint256_mul(thisAuction.discountRate, blocksElapsedUint)
    assert carry = Uint256(0, 0)

    # Price = StartPrice - Discount
    let (res) = uint256_sub(thisAuction.startingPrice, discount)
    return (res)
end


#
# Setters
#


@external
func initialize{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        nftAddress : felt,
        tokenId : Uint256,
        erc20Address : felt,
        startingPrice : Uint256,
        discountRate : Uint256,
        durationBlocks : felt,
    ):
    # Require not initialized
    let (_isInitialized) = isInitialized()
    with_attr error_message("auction already initialized"):
        assert _isInitialized = FALSE
    end

    # Require seller owns the token
    let (seller) = get_caller_address()
    let (tokenOwner) = IERC721.ownerOf(nftAddress, tokenId)
    with_attr error_message("auction already initialized"):
        assert seller = tokenOwner
    end

    let (startBlock) = get_block_number()
    let newAuction = Auction(
        nftAddress=nftAddress,
        tokenId=tokenId,
        seller=seller,
        erc20Address=erc20Address,
        startingPrice=startingPrice,
        discountRate=discountRate,
        startBlock=startBlock,
        durationBlocks=durationBlocks,
        sold=FALSE,
    )
    auction.write(newAuction)
    return ()
end


@external
func buy{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        value : Uint256,  # Denominated in auction's configured ERC20
    ):
    alloc_locals
    let (local thisAuction) = auction.read()

    # Require initialized
    let (_isInitialized) = isInitialized()
    with_attr error_message("auction not initialized"):
        assert _isInitialized = TRUE
    end

    # Require not expired
    let (currentBlock) = get_block_number()
    with_attr error_message("auction expired"):
        assert_le(
            currentBlock,
            thisAuction.startBlock + thisAuction.durationBlocks,
        )
    end

    # Require not seller
    let (buyer) = get_caller_address()
    with_attr error_message("auction not initialized"):
        assert_not_equal(thisAuction.seller, buyer)
    end

    # Require not sold
    with_attr error_message("auction not initialized"):
        assert thisAuction.sold = FALSE
    end

    # Require sent value >= price
    let (price) = getPrice()
    let (is_valid_bid) = uint256_le(price, value)
    with_attr error_message("bid value < price"):
        assert is_valid_bid = TRUE
    end

    # =========================================================================
    # Buy preconditions met
    # =========================================================================

    # Transfer ERC20 payment from buyer to seller
    IERC20.transferFrom(
        thisAuction.erc20Address,
        buyer,
        thisAuction.seller,
        value,
    )

    # Transfer the token from seller to buyer
    IERC721.transferFrom(
        thisAuction.nftAddress,
        thisAuction.seller,
        buyer,
        thisAuction.tokenId,
    )

    # Mark as sold
    let uninitializedAuction = Auction(
        nftAddress=thisAuction.nftAddress,
        tokenId=thisAuction.tokenId,
        seller=thisAuction.seller,
        erc20Address=thisAuction.erc20Address,
        startingPrice=thisAuction.startingPrice,
        discountRate=thisAuction.discountRate,
        startBlock=thisAuction.startBlock,
        durationBlocks=thisAuction.durationBlocks,
        sold=TRUE,
    )
    auction.write(value=uninitializedAuction)
    return ()
end


#
# Utils
#


func felt_to_uint256{range_check_ptr}(x) -> (x_ : Uint256):
    let split = split_felt(x)
    return (Uint256(low=split.low, high=split.high))
end
