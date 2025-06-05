// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * 
 * This contract deploys a simple auction system, that lasts for a day
 * it has a minimun bid value of 1.000.000 Wei and all bids have to be multiples of the min bid.
 * Only bidders distinct to the owner can use the bid() function
 * There can be partial claims of the deposited currency, leaving only the last bid of each address after every partial claim.
 * When Auction is over, the owner can send the reamining balances to each address discounting a 2% for gas purposes.
 * The owner can claim the remaining balance of the contract only after sending Ethers to the bidders have been done.
 *
*/

contract Auction {
    // storage variables
    address private owner;
    uint256 internal auctionStartDate;
    uint256 internal auctionEndDate;
    uint256 public minBid;

    // state variables 
    bool internal auctionEnded;
    bool internal withdrawPending;

    /// Constructor and initialization of storage and state variables 
    constructor() {
        owner = msg.sender;
        auctionStartDate = block.timestamp; 
        auctionEndDate = auctionStartDate + 1 days;
        minBid = 1000000 wei;
        auctionEnded = false;
        withdrawPending = false;
    } 

    // Structure for arrays and winner templates
    struct Offer {
        address offerer;
        uint256 value;
	} 
    
    // Array that will contain all Bids from all addresses
    Offer[] internal offers;
    // Var with the current winner of the auction =  last bidder, as it can only raise.
    Offer internal winner;

    /**
     * Events that will happen during the Auction
     * Every time a new offer is bid it will launch NewOffer
     * When the Auction ends it will trigger the AuctionEnded Event
     * When a withdraw is called we send an event indicating the address and the ammount withdrawed.
     * When almost over there could be a change in the End Date, so we send an event to display the new end date of the auction.
    */
    event NewOffer(uint256 _value, address indexed _offerer, uint256 _auctionStartDate, uint256 _auctionEndDate);
    event AuctionEnded(uint256 _auctionEndDate);
    event NewClaim(address indexed _offerer, uint256 _value);
    event NewAuctionEndDate(uint256 _auctionEndDate);

    /// Mapping for current balance of each bidder
    mapping (address => uint256) internal pendingBalances;
    /// Mapping with the last offer of each bidder.
    mapping (address => uint256) internal lastOfferPerAddress;

    /**
     * Resctrictions and validation of funtions usage.
     * We validate for valid offers, that include bid > 5% of last offer
     * Bid has to be multiple of minBid and bid > minBid
     * If the bidder is the same as the last bidder we revert
    */
    modifier validateOffer(uint256 _value) {
        require(_value >= minBid && _value % minBid == 0, "Error: values has to be multiples of 1.000.000 Wei."); 
        require(winner.value * 105 / 100 <= _value, "Error: New bid should be at least 5% higher than last offer.");
        require(msg.sender != winner.offerer, "Error: You are the last bidder.");
        _; 
    }   
    /// validate that the execution is happening between the auction start and end dates.
    modifier validateAuctionDates {
        require(block.timestamp > auctionStartDate, "Error: Auction has not started."); 
        require(block.timestamp < auctionEndDate, "Error: Auction already ended.");
        _;
    }
    /// Some functions will be restricted to the Owner with this modifier.
    modifier onlyOwner {
        require(msg.sender == owner, "Error: You are not the owner."); 
        _;
    }
    /// Some function won't be available for Owner to execute, example the Owner won't be able to bid in the auction.
    modifier notOwnerOnly {
        require(msg.sender != owner, "Error: Owner can not use this function.");
        _;
    }
    /// functions with isAuctionEnd can only be executed at the end of the auction.
    modifier isAuctionEnd {
        require(auctionEnded, "Error: Auction is not Over.");
        _;
    }
    /// Partial claim can only be executed while the contract is running
    modifier canMakePartialClaim {
        require(!auctionEnded,"Error: Auction is already over, wait for the Owner to Refound bids.");
        _;
    }
    /// Verify that all claims has been done before taking out profits from contract.
    modifier ownerCanClaim {
        require(withdrawPending, "Error: You need to send the pending Balances first.");
        _;
    }

    /**
     * Function that allows to retrieve Ethers from loosing bids
    */

    function partialClaim() external notOwnerOnly canMakePartialClaim {
        endAuction();
        address _addr = msg.sender;
        uint256 _lastOffer = lastOfferPerAddress[msg.sender];
        uint256 _actualBalance = pendingBalances[msg.sender];
        uint256 _total = _actualBalance - _lastOffer;
        require(_lastOffer < _actualBalance, "Error: Last bid will be refounded at the end of the Auction.");
        pendingBalances[_addr] = _lastOffer;
        withdraw(_addr, _total);
        emit NewClaim(_addr, _total);
    }

    /**
     * Send Ethers left in balance when Auction ended to their owners, 
    */
    function totalClaim() external isAuctionEnd onlyOwner {
        address _addr;
        uint256 _total;
        
        for (uint256 i = 0; i < offers.length; i++ ) {
            if (pendingBalances[offers[i].offerer] > 0) {
                _total = pendingBalances[offers[i].offerer] - (winner.offerer == offers[i].offerer ? winner.value : 0);
                _addr = offers[i].offerer;
                pendingBalances[offers[i].offerer] = 0;
                
                _total = _total * 98 / 100;
                withdraw(_addr, _total);
                emit NewClaim(_addr, _total);   
            }
        }
        withdrawPending = true;
    }
    /**
     * Retrieve profits from Auction to the owner of the contract.
    */
    function claimOwnerWin() external onlyOwner isAuctionEnd ownerCanClaim {
        uint256 _value = showBalance();
        withdraw(msg.sender, _value);

    }
    /**
     * Common withdraw function for all Claims.
    */
    function withdraw(address _addr, uint256 _value) internal {
        (bool _result,) = _addr.call{value: _value}("");
        require(_result, "Error: Unable to send Ether, please try again.");  
    }

    /// Function that allows to set a Bid for the Auction only for address distinct to the Owner.
    function bid() external payable notOwnerOnly validateOffer(msg.value) validateAuctionDates {
        uint256 _value = msg.value;
        endAuction();  
        offers.push(Offer(msg.sender,_value));   
        winner.offerer = msg.sender;
        winner.value = _value;
        pendingBalances[msg.sender] += _value; 
        lastOfferPerAddress[msg.sender] = _value;
        emit NewOffer(_value, msg.sender, auctionStartDate, auctionEndDate); 
        if (block.timestamp >= auctionEndDate - 10 minutes && block.timestamp < auctionEndDate) {
            auctionEndDate += 10 minutes;
            emit NewAuctionEndDate(auctionEndDate);
        }
    }
    /// Displays the final winner of the auction.
    function showWinner() external view isAuctionEnd returns(address, uint256) {
        return (winner.offerer,winner.value);    
    }   

    // Displays all bids of the auction.
    function showOffers() external view returns(Offer[] memory) {
        return offers;
    }

    // Internal function to obtain the currect balance of the contract
    function showBalance() internal view returns(uint256) {
        return address(this).balance;
    }  

    /// Displays the last offer done in the Auction
    function showAuctionLastOffer() external view returns(uint256) {
        return winner.value;
    }

    // internal function that checks if the timestamp is greater that the end date so if changes states for the auction.
    function endAuction() internal {
        if (block.timestamp >= auctionEndDate){    
            emit AuctionEnded(auctionEndDate); 
            auctionEnded = true;
        } 
    }
    // Function to allow the owner to forcibly finish the auction 
    function finalizeAuctionByOwner() external onlyOwner {
        auctionEndDate = block.timestamp;
        auctionEnded = true;
        emit AuctionEnded(auctionEndDate);
    }
    /// Show Start and End time of auction.
    function checkAuctionDates() external view returns (uint256, uint256) {
        return (auctionStartDate, auctionEndDate); 
    }

}

