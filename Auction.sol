// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Simple Auction contract 
 * @notice This contract deploys a simple auction system, that lasts for a day
 * it has a minimun bid value of 1.000.000 Wei and all bids have to be multiples of the min bid.
 * @dev features include:
 * - Only bidders distinct to the owner can use the bid() function
 * - There can be partial claims of the deposited currency, leaving only the last bid of each address after every partial claim.
 * - When Auction is over, the owner can send the reamining balances to each address discounting a 2% for gas purposes.
 * - The owner can claim the remaining balance of the contract only after sending Ethers to the bidders have been done.
 * - In the last 10 minutes of the auction the time extends by 10 minutes with every new offer.
 *
*/

contract Auction {
    /// address of the contract owner
    address private owner;
    /// Auction Start date
    uint256 internal auctionStartDate;
    /// Auction End Date
    uint256 internal auctionEndDate;
    /// minimun Bid allowed by the contract.
    uint256 public minBid;

    /// Variable to check if auction its closed and validations
    bool internal isAuctionEnded;
    /// Variable to lock owner contract withdrawal until then pending balances are sent.
    bool internal withdrawPending;

    /**
     * @notice Initialize the auction contract variables.
     * @dev Sets the contract owner as the account deploying the contract, the minumun bid, Auction Start time and End Time.
    */
    constructor() {
        owner = msg.sender;
        auctionStartDate = block.timestamp; 
        auctionEndDate = auctionStartDate + 1 days;
        minBid = 1000000 wei;
        isAuctionEnded = false;
        withdrawPending = false;
    } 

    /**
     * @title Bid Structure
     * @notice Representation of a the bid object for the auction
    */
    struct Offer {
        /// @notice Address of the offerer in the bid function
        address offerer;
        /// @notice Bid Value set by the offerer
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

    /**
     * @dev Emits NewOffer everytime an user sets a new bid in the auction
     * @param _offerer Address that sets the new offer in the auction
     * @param _value the ammount offered by the address
     * @param _auctionStartDate value of the auction start time
     * @param _auctionEndDate value of the current end Date for the auction
    */
    event NewOffer(uint256 _value, address indexed _offerer, uint256 _auctionStartDate, uint256 _auctionEndDate);
    
    /**
     * @dev Emits AuctionEnded when the Auction reach the AuctionEndTime
     * @param _auctionEndDate send the end time of the auction
    */
    
    event AuctionEnded(uint256 _auctionEndDate);
    /**
     * @dev Emits NewClaim everytime an user makes a partial claim, or the funds are refunded.
     * @param _offerer the address that receives the claim
     * @param _value the ammount sent to the user address
    */
    
    event NewClaim(address indexed _offerer, uint256 _value);
    /**
     * @dev Emits NewAuctionEndDate everytime an user sets a new bid and changes the auctionEndDate we sent and event indicating the change.
     * @param _auctionEndDate Displays the new End Date for the Auction
    */
    
    event NewAuctionEndDate(uint256 _auctionEndDate);
    /**
     * @dev Emits EmergencyAuctionEnd when the owner forcibly ends the auction and claims the balance.
     * @param _owner displays the auction owner address 
     * @param _auctionEndDate Displays End Date for the Auction when the owner closed the auction.
    */
    event EmergencyAuctionClaim(address indexed _owner, uint256 _balanceValue, uint256 _auctionEndDate);

    /// Mapping for current balance of each bidder
    mapping (address => uint256) internal pendingBalances;
    /// Mapping with the last offer of each bidder.
    mapping (address => uint256) internal lastOfferPerAddress;

    /**
     * @dev Modifier that validates that all premises before a bid can be placed
     * @notice Reverts if any of the premises is not acomplished 
     * - Bid have to be set between the Start and End date of the auction
     * - Bid must be at least equal or higher that the minimun Bid allowed
     * - Bid must be at least 5% higher than last bid.
     * - The Owner can't bid in the Auction.
    */
    modifier validateOffer(uint256 _value) {
        require(block.timestamp > auctionStartDate, "Auction Not Started"); 
        require(block.timestamp < auctionEndDate, "Auction Ended");
        require(_value >= minBid && _value % minBid == 0, "Bid higher than Min Bid"); 
        require(winner.value * 105 / 100 <= _value, "Bid must be higher");
        require(msg.sender != winner.offerer, "Current last bidder.");
        _; 
    }   
    /** 
     * @dev Modifier that allows the only the owner of the contract to access to certain functions
     * @notice Reverts if the caller of the function is distinct to the owner of the contract.
    */
    modifier onlyOwner {
        require(msg.sender == owner, "Not the Owner."); 
        _;
    }
    /**
     * @dev Modifier that allows only users different to the owner of the contract to use some of the functions
     * @notice Reverts if the caller of the function is the Owner.
    */
    modifier notOwnerOnly {
        require(msg.sender != owner, "Only Users.");
        _;
    }
    /** 
     * @dev Modifier that stop execution of the functions in case the auction is not over.
     * @notice Reverts in case a function is called and the auction is not over yet.    
    */
    modifier isAuctionEnd {
        require(isAuctionEnded, "Auction Not Over.");
        _;
    }
    /**
     * @dev Modifier that allows Auction Users to make partial claims while the auction is running.
     * @notice Reverts in case the auction end time is reached and doesn't allow to make any more partial claims of the balances.
    */
    modifier canMakePartialClaim {
        require(!isAuctionEnded,"Auction Over, wait Refund.");
        _;
    }
    /**
     * @dev Modifier that stops the owner to transfer all the contract balance before sending the refunds to all users.
     * @notice Reverts in case Owner call the function and haven't send the pending balances of the users.
    */
    modifier ownerCanClaim {
        require(withdrawPending, "Send pending Balances.");
        _;
    }

    /**
     * @notice makes a partial claim of the pendingBalances of the Address
     * @dev Requirements:
     * - Auction must be active
     * - Only the address that has the bid can make the claim
     * - Owner can't use this function.
     * - Only balances prior to last bid can be partial claimed.
     * @dev Effects:
     * - Transfer all the balance to the address calling the function, except for it's last bid.
     * @custom:reverts if the Owner of the contract calls the function.
     * @custom:reverts in case the auction has ended.
    */
    function partialClaim() external notOwnerOnly canMakePartialClaim {
        endAuction();
        address _addr = msg.sender;
        uint256 _lastOffer = lastOfferPerAddress[_addr];
        uint256 _actualBalance = pendingBalances[_addr];
        require(_lastOffer < _actualBalance, "Can't claim last bid.");
        uint256 _total = _actualBalance - _lastOffer;
        pendingBalances[_addr] = _lastOffer;
        withdraw(_addr, _total);
        emit NewClaim(_addr, _total);
    }


    /**
     * @notice makes the transfer of all the remamining balances in the contract after the auction End.
     * @dev Requirements:
     * - Auction must have ended.
     * - Only the Owner of the contract can call the function.
     * @dev Effects:
     * - Transfer the pending balances to the addresses in pendingBalances.
     * - Reserve a 2% of the pending balances for Gas costs on the transfers.
     * - The winner only gets all pending balances prior to the winning offer.
     * - Set addresses balances to 0 in the contract.
     * - Set the owner able to claim all the remaining balance of the contract.
     * @custom:reverts if the the address calling the function is not the owner.
     * @custom:reverts if the auction is still running.
    */
    function totalClaim() external onlyOwner isAuctionEnd {
        address _addr;
        uint256 _total;
        uint256 _len = offers.length;
        
        for (uint256 i = 0; i < _len; i++ ) {
            _addr = offers[i].offerer;
            if (pendingBalances[_addr] > 0) {
                _total = pendingBalances[_addr] - (winner.offerer == _addr ? winner.value : 0);
                pendingBalances[_addr] = 0;
                _total = _total * 98 / 100;
                withdraw(_addr, _total);
                emit NewClaim(_addr, _total);   
            }
        }
        withdrawPending = true;
    }
    
    /**
     * @notice Retrieves the contract balances to the owner address.
     * @dev Requirements:
     * - Auction must have ended.
     * - Only the Owner of the contract can call the function.
     * - Must have send the remaining balances to all the accounts that used the auction.
     * @dev Effects:
     * - Transfer the pending balances of the contract to the owner
     * @custom:reverts if the the address calling the function is not the owner.
     * @custom:reverts if the auction is still running.
     * @custom:reverts if the owner have not send the remining balances to the users address
    */
    function claimOwnerWin() external onlyOwner isAuctionEnd ownerCanClaim {
        uint256 _value = showBalance();
        withdraw(msg.sender, _value);

    }
    /**
     * @notice Internal function that makes the transfer call and verify that it reached the address.
     * @dev Requirements:
     * - Must be called from within other function.
     * - Must reach the destination 
     * @dev Effects:
     * - Transfer the pending balances to the reciever address.
     * - Reverts if the funds sent doesn't reach the address.
    */
    function withdraw(address _addr, uint256 _value) internal {
        (bool _result,) = _addr.call{value: _value}("");
        require(_result, "Unable to send, try again");  
    }
    /**
     * @notice Function to claim all the balance of the contract to the owner in case an emergency 
     * @dev Requirements:
     * - Must be the owner of the contract.
     * - The Auction must have ended status
     * @dev Effects:
     * - Send all the balance in the contract to contract owner
     * - Emits Event indicating that the emergency claim was called
    */
    function emergencyClaim() external onlyOwner isAuctionEnd {
        uint256 _withdrawBalance = showBalance();
        withdraw(owner, _withdrawBalance);
        emit EmergencyAuctionClaim(owner, _withdrawBalance, auctionEndDate);
    }


    /**
     * @notice bid() Allows to place offers in the auction
     * @dev Requirements:
     * - Only Addresses different to the owner can place offers
     * - Bid must be between the start and end dates of the auction
     * - Value must be higher than minimun bid
     * - Offers must be at least 5% higher than last offer.
     * @dev Effects:
     * - Place a new bid in the offers array for the address
     * - update pendingBalances mapping for the address that placed the bid.
     * - updates current winner and winner offer with the last bid.
     * - Calls to end auction function and verify if already ended.
     * - Calls to verify auction enddate to extend time in case is needed.
     * @custom:reverts if the address bidding is the owner
     * @custom:reverts if the offer doesn't comply to the requirements.
     * @custom:reverts if the auction is already past the end time of the auction.
    */
    function bid() external payable notOwnerOnly validateOffer(msg.value) {
        uint256 _value = msg.value;
        endAuction();  
        offers.push(Offer(msg.sender,_value));   
        winner.offerer = msg.sender;
        winner.value = _value;
        pendingBalances[msg.sender] += _value; 
        lastOfferPerAddress[msg.sender] = _value;
        emit NewOffer(_value, msg.sender, auctionStartDate, auctionEndDate); 
        verifyAuctionEndDate();
    }
    /**
     * @notice Internal Function to verify if the end time for the auction is under 10 minutes and extends the time for 10 minutes more
     * @dev Requirements:
     * - Must be called from with a function of the contract.
     * @dev Effects:
     * - Verify the end time of the contract and extends the duration by 10 minutes in case it apply.
    */
    function verifyAuctionEndDate() internal {
        if (block.timestamp >= auctionEndDate - 10 minutes && block.timestamp < auctionEndDate) {
            auctionEndDate += 10 minutes;
            emit NewAuctionEndDate(auctionEndDate);
        }
    }
    /**
     * @notice External function to display the winner of the Auction.
     * @dev Requirements:
     * - Auction must have ended to display the winner.
     * @dev Effects:
     * - returns the winner and value of the winner offer of the auction
     * @custom:reverts in case the auction have not ended.
    */
    function showWinner() external view isAuctionEnd returns(address, uint256) {
        return (winner.offerer,winner.value);    
    }   

    /**
     * @notice External function that returns the offers array with all addresses and offers 
     * @dev Effects:
     * - returns all the offers with the address who offered.
    */
    function showOffers() external view returns(Offer[] memory) {
        return offers;
    }

    /**
     * @notice internal function that return the current balance of the contract. 
     * @dev Effects:
     * - returns the current balance of the contract.
    */
    function showBalance() internal view returns(uint256) {
        return address(this).balance;
    }  

    /**
     * @notice function to display the last offer made to the contract. 
     * @dev Effects:
     * - returns the last offer value
    */
    function showAuctionLastOffer() external view returns(uint256) {
        return winner.value;
    }

    /**
     * @notice internal function that verify the end time of the auction and set the auction end variable.
     * @dev Effects:
     * - Compare the current timestamp with the end time of the auction
     * - set the Auction end variable to true
     * - Emits the AuctionEnded event.
     * @custom:reverts in case the caller is distinct to the owner.
    */
    function endAuction() internal {
        if (block.timestamp >= auctionEndDate){    
            isAuctionEnded = true;
            emit AuctionEnded(auctionEndDate); 
        } 
    }
    /**
     * @notice internal function to forcibly set the end of the auction to the current timestamp.
     * @dev Effects:
     * - Set the auctionEndDate to the current timestamp.
     * - call the endAuction function to finish the auction.
     * @custom:reverts in case the caller is distinct to the owner.
    */
    function finalizeAuctionByOwner() external onlyOwner {
        auctionEndDate = block.timestamp;
        endAuction();
    }

    /**
     * @notice Function that returns the currect Start and End Dates of the Auction.
     * @dev Effects:
     * - Returns the current Start and End time of the auction.
    */
    function checkAuctionDates() external view returns (uint256, uint256) {
        return (auctionStartDate, auctionEndDate); 
    }

}
