# SPDX-License-Identifier: MIT
# OpenZeppelin Cairo Contracts v0.1.0 (token/erc20/ERC20_Mintable.cairo)

%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import (Uint256, uint256_le)
from starkware.starknet.common.syscalls import (
    get_block_number,
    get_block_timestamp,
    get_caller_address,
    get_contract_address
)
from starkware.cairo.common.math import (
    assert_not_zero,
    assert_nn_le,
    split_felt
)

from openzeppelin.token.erc20.library import (
    ERC20_name,
    ERC20_symbol,
    ERC20_totalSupply,
    ERC20_decimals,
    ERC20_balanceOf,
    ERC20_allowance,

    ERC20_initializer,
    ERC20_approve,
    ERC20_increaseAllowance,
    ERC20_decreaseAllowance,
    ERC20_transfer,
    ERC20_transferFrom,
    ERC20_mint
)

from openzeppelin.access.ownable import (
    Ownable_initializer,
    Ownable_only_owner
)

from openzeppelin.utils.constants import TRUE

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
func emissionRate() -> (res : felt):
end

# parameter that controls price decay, stored as a 59x18 fixed precision number
@storage_var
func decayConstant() -> (res : felt):
end

# start time for all auctions, stored as a 59x18 fixed precision number
@storage_var
func lastAvailableAuctionStartTime() -> (res : felt):
end

@constructor
func constructor{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        name: felt,
        symbol: felt,
        owner: felt,
        _initialPrice: felt,
        _emissionRate: felt,
        _decayConstant: felt
    ):
    ERC20_initializer(name, symbol, 18)
    Ownable_initializer(owner)
    # Write initial values
    initialPrice.write(_initialPrice)
    emissionRate.write(_emissionRate)
    decayConstant.write(_decayConstant)

    let (block_timestamp) = get_block_timestamp()
    let (fixedTimestamp) = Math64x61_fromFelt(block_timestamp)
    lastAvailableAuctionStartTime.write(fixedTimestamp)
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

    let (block_timestamp) = get_block_timestamp()
    let (fixed_timestamp) = Math64x61_fromFelt(block_timestamp)
    let (last_time) = lastAvailableAuctionStartTime.read()
    let (emission_rate) = lastAvailableAuctionStartTime.read()
    # number of seconds of token emissions that are available to be purchased
    let (seconds_of_emission_available) = Math64x61_sub(fixed_timestamp, last_time)
    let (fixed_num_tokens) = Math64x61_fromFelt(numTokens)
    # number of seconds of emissions are being purchased
    let (seconds_of_emission_to_purchase) = Math64x61_div(numTokens, emission_rate)

    with_attr error_message("insufficient available tokens"):
        assert_nn_le(seconds_of_emission_to_purchase, seconds_of_emission_available)
    end

    let (price) = purchase_price(numTokens)
    let (is_valid_bid) = uint256_le(price, value)
    with_attr error_message("insufficient payment"):
        assert is_valid_bid = TRUE
    end

    # Mint all tokens
    let (num_tokens) = felt_to_uint256(numTokens)
    ERC20_mint(to, num_tokens)

    # Update last available auction
    local new_time = last_time + seconds_of_emission_to_purchase
    lastAvailableAuctionStartTime.write(new_time)


    # Refund buyer for excess payment
    # let (buyer : felt) = get_caller_address()
    # let (contract_address : felt) = get_contract_address()
    # let (payment_token : felt) = erc20Address.read()
    # let (excess_price : Uint256) = uint256_sub(price, value)

    # let (success) = IERC20.transferFrom(
    #     payment_token,
    #     buyer,
    #     contract_address, 
    #     excess_price, # purchase price - value sent
    # )
    # with_attr error_message("unable to refund"):
    #     assert success = TRUE
    # end



    return ()
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

    let (quantity) = Math64x61_fromFelt(numTokens)
    let (local auction_start_time) = lastAvailableAuctionStartTime.read()
    let (block_timestamp) = get_block_timestamp()
    let (fixedTimestamp) = Math64x61_fromFelt(block_timestamp)
    let (time_since_start) = Math64x61_sub(fixedTimestamp, auction_start_time)

    let (local initial_price) = initialPrice.read()
    let (local decay_constant) = decayConstant.read()
    let (local emission_rate) = emissionRate.read()

    let (mul_num1) = Math64x61_mul(decay_constant, quantity)
    let (div_num1) = Math64x61_div(mul_num1, emission_rate)
    let (exp_num1) = Math64x61_exp(div_num1)

    let (num1) = Math64x61_div(initial_price, decay_constant)
    let (num2) = Math64x61_sub(exp_num1, Math64x61_ONE)

    let (mul_num2) = Math64x61_mul(decay_constant, time_since_start)
    let (den) = Math64x61_exp(mul_num2)

    let (num) = Math64x61_mul(num1, num2)
    let (total_cost) = Math64x61_div(num, den)
    let (total_cost_uint) = Math64x61_toUint256(total_cost)

    return (res=total_cost_uint)
end

@view
func name{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (name: felt):
    let (name) = ERC20_name()
    return (name)
end

@view
func symbol{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (symbol: felt):
    let (symbol) = ERC20_symbol()
    return (symbol)
end

@view
func totalSupply{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (totalSupply: Uint256):
    let (totalSupply: Uint256) = ERC20_totalSupply()
    return (totalSupply)
end

@view
func decimals{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (decimals: felt):
    let (decimals) = ERC20_decimals()
    return (decimals)
end

@view
func balanceOf{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt) -> (balance: Uint256):
    let (balance: Uint256) = ERC20_balanceOf(account)
    return (balance)
end

@view
func allowance{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(owner: felt, spender: felt) -> (remaining: Uint256):
    let (remaining: Uint256) = ERC20_allowance(owner, spender)
    return (remaining)
end

#
# Externals
#

@external
func transfer{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt, amount: Uint256) -> (success: felt):
    ERC20_transfer(recipient, amount)
    return (TRUE)
end

@external
func transferFrom{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        sender: felt, 
        recipient: felt, 
        amount: Uint256
    ) -> (success: felt):
    ERC20_transferFrom(sender, recipient, amount)
    return (TRUE)
end

@external
func approve{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(spender: felt, amount: Uint256) -> (success: felt):
    ERC20_approve(spender, amount)
    return (TRUE)
end

@external
func increaseAllowance{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(spender: felt, added_value: Uint256) -> (success: felt):
    ERC20_increaseAllowance(spender, added_value)
    return (TRUE)
end

@external
func decreaseAllowance{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(spender: felt, subtracted_value: Uint256) -> (success: felt):
    ERC20_decreaseAllowance(spender, subtracted_value)
    return (TRUE)
end

@external
func mint{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(to: felt, amount: Uint256):
    Ownable_only_owner()
    ERC20_mint(to, amount)
    return ()
end

#
# Utils
#


func felt_to_uint256{range_check_ptr}(x) -> (x_ : Uint256):
    let split = split_felt(x)
    return (Uint256(low=split.low, high=split.high))
end