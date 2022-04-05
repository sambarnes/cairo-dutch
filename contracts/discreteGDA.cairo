%lang starknet

from openzeppelin.token.erc721.interfaces.IERC721 import IERC721

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.starknet.common.syscalls import (
    get_block_number,
    get_block_timestamp,
    get_caller_address,
)

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

from openzeppelin.access.ownable import (
    Ownable_initializer,
    Ownable_only_owner
)

from contracts.Math64x61 import ( 
    Math64x61_fromFelt, 
    Math64x61_toFelt 
)

#
# Storage
#

@storage_var
func currentId() -> (res : felt):
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
