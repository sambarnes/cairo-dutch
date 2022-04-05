%lang starknet

from openzeppelin.token.erc721.interfaces.IERC721 import IERC721

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import (
    get_block_number,
    get_block_timestamp,
    get_caller_address,
    get_contract_address
)
from openzeppelin.utils.constants import FALSE, TRUE

from openzeppelin.token.erc721.library import (
    ERC721_name,
    ERC721_symbol,
    ERC721_balanceOf,
    ERC721_ownerOf,
    ERC721_getApproved,
    ERC721_isApprovedForAll,
    ERC721_tokenURI,

    ERC721_initializer,
    ERC721_approve, 
    ERC721_setApprovalForAll, 
    ERC721_transferFrom,
    ERC721_safeTransferFrom,
    ERC721_mint,
    ERC721_setTokenURI
)

from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_le,
    uint256_mul,
    uint256_sub,
)

from openzeppelin.access.ownable import (
    Ownable_initializer,
    Ownable_only_owner
)
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20


from contracts.Math64x61 import ( 
    Math64x61_fromFelt, 
    Math64x61_toFelt,
    Math64x61_sub,
    Math64x61_mul,
    Math64x61_div,
    Math64x61_pow,
    Math64x61_exp
)

#
# Storage
#

@storage_var
func currentId() -> (res : felt):
end

# parameter that controls which erc20 should be used to purchase tokens
@storage_var
func erc20Address() -> (res : felt):
end

# parameter that controls initial price, stored as a 59x18 fixed precision number
@storage_var
func initialPrice() -> (res : felt):
end

# parameter that controls how much the starting price of each successive auction increases by,
# stored as a 59x18 fixed precision number
@storage_var
func scaleFactor() -> (res : felt):
end

# parameter that controls price decay, stored as a 59x18 fixed precision number
@storage_var
func decayConstant() -> (res : felt):
end

# start time for all auctions, stored as a 59x18 fixed precision number
@storage_var
func auctionStartTime() -> (res : felt):
end


#
# Constructor
#

@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        name: felt,
        symbol: felt,
        owner: felt,
        _initialPrice: felt,
        _scaleFactor: felt,
        _decayConstant: felt
    ):
    # Construct Parents
    ERC721_initializer(name, symbol)
    Ownable_initializer(owner)
    # Write initial values
    initialPrice.write(_initialPrice)
    scaleFactor.write(_scaleFactor)
    decayConstant.write(_decayConstant)

    let (block_timestamp) = get_block_timestamp()
    let (fixedTimestamp) = Math64x61_fromFelt(block_timestamp)
    auctionStartTime.write(fixedTimestamp)
    return ()
end

# purchase a specific number of tokens from the GDA
@external
func purchaseTokens{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        numTokens : felt,  
        to: felt,
        value: Uint256 # Denominated in auction's configured ERC20
    ):
    alloc_locals

    let (price) = purchase_price()
    let (is_valid_bid) = uint256_le(price, value)
    with_attr error_message("insufficient payment"):
        assert is_valid_bid = TRUE
    end

    # Mint all tokens
    _mint_batch(to, numTokens)


    # Refund buyer for excess payment
    let (buyer) = get_caller_address()
    let (contract_address) = get_contract_address()
    let (success) = IERC20.transferFrom(
        erc20Address.read(),
        buyer,
        contract_address, 
        uint256_sub(price, value), # purchase price - value sent
    )
    with_attr error_message("unable to refund"):
        assert success = TRUE
    end



    return ()
end

func _mint_batch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        to : felt, amount : felt) -> ():
    assert_not_zero(to)

    if amount == 0:
        return ()
    end

    let (current_id) = currentId.read()
    _mint(to, current_id)

    currentId.write(current_id + 1)

    return _mint_batch(
        to=to,
        amount=(amount - 1))
end

#
# Getters
#

@view
func purchase_price{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(numTokens: felt) -> (res: felt):
    let (quantity) = Math64x61_fromFelt(numTokens)
    let (num_sold) = Math64x61_fromFelt(currentId.read())

    let (block_timestamp) = get_block_timestamp()
    let (fixedTimestamp) = Math64x61_fromFelt(block_timestamp)
    let (time_since_start) = Math64x61_sub(fixedTimestamp, auctionStartTime.read())

    let (scale_factor) = scaleFactor.read()

    let (num1) = Math64x61_mul(initialPrice.read(), Math64x61_pow(scale_factor, num_sold))
    let (num2) = Math64x61_sub(Math64x61_pow(scale_factor, quantity), Math64x61_fromFelt(1))
    let (den1) = Math64x61_exp(Math64x61_mul(decayConstant.read(), time_since_start)) 
    let (den2) = Math64x61_sub(scale_factor, Math64x61_fromFelt(1))

    let (total_cost) = Math64x61_div(Math64x61_mul(num1, num2), Math64x61_mul(den1, den2))

    return (res=total_cost)
end

#
# ERC721_Mintable_Burnable
#

#
# Getters
#

@view
func supportsInterface{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(interfaceId: felt) -> (success: felt):
    let (success) = ERC165_supports_interface(interfaceId)
    return (success)
end

@view
func name{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (name: felt):
    let (name) = ERC721_name()
    return (name)
end

@view
func symbol{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (symbol: felt):
    let (symbol) = ERC721_symbol()
    return (symbol)
end

@view
func balanceOf{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(owner: felt) -> (balance: Uint256):
    let (balance: Uint256) = ERC721_balanceOf(owner)
    return (balance)
end

@view
func ownerOf{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tokenId: Uint256) -> (owner: felt):
    let (owner: felt) = ERC721_ownerOf(tokenId)
    return (owner)
end

@view
func getApproved{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tokenId: Uint256) -> (approved: felt):
    let (approved: felt) = ERC721_getApproved(tokenId)
    return (approved)
end

@view
func isApprovedForAll{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(owner: felt, operator: felt) -> (isApproved: felt):
    let (isApproved: felt) = ERC721_isApprovedForAll(owner, operator)
    return (isApproved)
end

@view
func tokenURI{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*, 
        range_check_ptr
    }(tokenId: Uint256) -> (tokenURI: felt):
    let (tokenURI: felt) = ERC721_tokenURI(tokenId)
    return (tokenURI)
end


#
# Externals
#

@external
func approve{
        pedersen_ptr: HashBuiltin*, 
        syscall_ptr: felt*, 
        range_check_ptr
    }(to: felt, tokenId: Uint256):
    ERC721_approve(to, tokenId)
    return ()
end

@external
func setApprovalForAll{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*, 
        range_check_ptr
    }(operator: felt, approved: felt):
    ERC721_setApprovalForAll(operator, approved)
    return ()
end

@external
func transferFrom{
        pedersen_ptr: HashBuiltin*, 
        syscall_ptr: felt*, 
        range_check_ptr
    }(
        _from: felt, 
        to: felt, 
        tokenId: Uint256
    ):
    ERC721_transferFrom(_from, to, tokenId)
    return ()
end

@external
func safeTransferFrom{
        pedersen_ptr: HashBuiltin*, 
        syscall_ptr: felt*, 
        range_check_ptr
    }(
        _from: felt, 
        to: felt, 
        tokenId: Uint256,
        data_len: felt, 
        data: felt*
    ):
    ERC721_safeTransferFrom(_from, to, tokenId, data_len, data)
    return ()
end

@external
func setTokenURI{
        pedersen_ptr: HashBuiltin*, 
        syscall_ptr: felt*, 
        range_check_ptr
    }(tokenId: Uint256, tokenURI: felt):
    Ownable_only_owner()
    ERC721_setTokenURI(tokenId, tokenURI)
    return ()
end

@external
func mint{
        pedersen_ptr: HashBuiltin*, 
        syscall_ptr: felt*, 
        range_check_ptr
    }(to: felt, tokenId: Uint256):
    Ownable_only_owner()
    ERC721_mint(to, tokenId)
    return ()
end

@external
func burn{
        pedersen_ptr: HashBuiltin*, 
        syscall_ptr: felt*, 
        range_check_ptr
    }(tokenId: Uint256):
    ERC721_only_token_owner(tokenId)
    ERC721_burn(tokenId)
    return ()
end
