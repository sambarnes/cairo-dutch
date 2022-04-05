%lang starknet

from openzeppelin.token.erc721.interfaces.IERC721 import IERC721

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import (
    get_block_number,
    get_block_timestamp,
    get_caller_address,
    get_contract_address
)
from starkware.cairo.common.math import (
    assert_not_zero,
    split_felt
)
from openzeppelin.utils.constants import FALSE, TRUE
from openzeppelin.introspection.ERC165 import ERC165_supports_interface
from openzeppelin.token.erc721.library import (
    ERC721_name,
    ERC721_symbol,
    ERC721_balanceOf,
    ERC721_ownerOf,
    ERC721_getApproved,
    ERC721_isApprovedForAll,
    ERC721_tokenURI,
    ERC721_only_token_owner,
    ERC721_initializer,
    ERC721_approve, 
    ERC721_setApprovalForAll, 
    ERC721_transferFrom,
    ERC721_safeTransferFrom,
    ERC721_mint,
    ERC721_burn,
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
    Math64x61_exp,
    Math64x61_toUint256,
    Math64x61_ONE
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

    let (price) = purchase_price(numTokens)
    let (is_valid_bid) = uint256_le(price, value)
    with_attr error_message("insufficient payment"):
        assert is_valid_bid = TRUE
    end

    # Mint all tokens
    _mint_batch(to, numTokens)


    # Refund buyer for excess payment
    let (buyer : felt) = get_caller_address()
    let (contract_address : felt) = get_contract_address()
    let (payment_token : felt) = erc20Address.read()
    let (excess_price : Uint256) = uint256_sub(price, value)

    let (success) = IERC20.transferFrom(
        payment_token,
        buyer,
        contract_address, 
        excess_price, # purchase price - value sent
    )
    with_attr error_message("unable to refund"):
        assert success = TRUE
    end



    return ()
end

func _mint_batch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        to : felt, amount : felt) -> ():
    alloc_locals
    assert_not_zero(to)

    if amount == 0:
        return ()
    end

    let (local current_id) = currentId.read()
    let (current_id_uint : Uint256) = felt_to_uint256(current_id)
    ERC721_mint(to, current_id_uint)

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
    }(numTokens: felt) -> (res: Uint256):
    alloc_locals

    let (local current_id) = currentId.read()
    let (local auction_start_time) = auctionStartTime.read()
    let (local initial_price) = initialPrice.read()
    let (local decay_constant) = decayConstant.read()

    let (quantity) = Math64x61_fromFelt(numTokens)
    let (num_sold) = Math64x61_fromFelt(current_id)

    let (block_timestamp) = get_block_timestamp()
    let (fixedTimestamp) = Math64x61_fromFelt(block_timestamp)
    let (time_since_start) = Math64x61_sub(fixedTimestamp, auction_start_time)

    let (scale_factor) = scaleFactor.read()

    let (local pow_num) = Math64x61_pow(scale_factor, num_sold)
    let (local pow_num2) = Math64x61_pow(scale_factor, quantity)
    let (local mul_num1) = Math64x61_mul(decay_constant, time_since_start)

    let (num1) = Math64x61_mul(initial_price, pow_num)
    let (num2) = Math64x61_sub(pow_num2, Math64x61_ONE)

    let (den1) = Math64x61_exp(mul_num1) 
    let (den2) = Math64x61_sub(scale_factor, Math64x61_ONE)

    let (local mul_num2) = Math64x61_mul(num1, num2)
    let (local mul_num3) = Math64x61_mul(den1, den2)

    let (local total_cost) = Math64x61_div(mul_num2, mul_num3)
    let (total_cost_uint) = Math64x61_toUint256(total_cost)

    return (res=total_cost_uint)
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

#
# Utils
#


func felt_to_uint256{range_check_ptr}(x) -> (x_ : Uint256):
    let split = split_felt(x)
    return (Uint256(low=split.low, high=split.high))
end