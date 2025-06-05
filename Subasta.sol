// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Subasta {

    address private owner;
    uint256 internal auctionStartDate;
    uint256 internal auctionEndDate;
    uint256 public minBid;
    bool internal auctionEnded;
    bool internal withdrawPending;
    
    constructor() {
        owner = msg.sender;
        auctionStartDate = block.timestamp; 
        auctionEndDate = auctionStartDate + 1 days;
        minBid = 1000000 wei;
        auctionEnded = false;
        withdrawPending = false;
    } 

    struct Offer {
        address offerer;
        uint256 value;
	} 
    
    Offer[] internal offers;
    Offer internal winner;

    event NewOffer(uint256 _value, address indexed _offerer, uint256 _auctionStartDate, uint256 _auctionEndDate);
    event AuctionEnded(uint256 _auctionEndDate);
    event NewClaim(address indexed _offerer, uint256 _value);
    event NewAuctionEndDate(uint256 _auctionEndDate);

    mapping (address => uint256) internal pendingBalances;
    mapping (address => uint256) internal lastOfferPerAddress;


    modifier validateOffer(uint256 _value) {
        require(_value >= minBid && _value % minBid == 0, "Error: values has to be multiples of 1.000.000 Wei."); 
        require(winner.value * 105 / 100 <= _value, "Error: New bid should be at least 5% higher than last offer.");
        require(msg.sender != winner.offerer, "Error: You are the last bidder.");
        _; 
    }   
    modifier validateAuctionDates {
        require(block.timestamp > auctionStartDate, "Error: Auction has not started."); 
        require(block.timestamp < auctionEndDate, "Error: Auction already ended.");
        _;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Error: You are not the owner."); 
        _;
    }

    modifier notOwnerOnly {
        require(msg.sender != owner, "Error: Owner can not use this function.");
        _;
    }

    modifier isAuctionEnd {
        require(auctionEnded, "Error: Auction is not Over.");
        _;
    }

    modifier canMakePartialClaim {
        require(!auctionEnded,"Error: Auction is already over, wait for the Owner to Refound bids.");
        _;
    }

    modifier ownerCanClaim {
        require(withdrawPending, "Error: You need to send the pending Balances first.");
        _;
    }

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

    function claimOwnerWin() external onlyOwner isAuctionEnd ownerCanClaim {
        uint256 _value = showBalance();
        withdraw(msg.sender, _value);

    }

    function withdraw(address _addr, uint256 _value) internal {
        (bool _result,) = _addr.call{value: _value}("");
        require(_result, "Error: Unable to send Ether, please try again.");  
    }

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

    function showWinner() external view isAuctionEnd returns(address, uint256) {
        return (winner.offerer,winner.value);    
    }   

    function showOffers() external view returns(Offer[] memory) {
        return offers;
    }

    function showBalance() internal view returns(uint256) {
        return address(this).balance;
    }  

    function showAuctionLastOffer() external view returns(uint256) {
        return winner.value;
    }

    function endAuction() internal {
        if (block.timestamp >= auctionEndDate){    
            emit AuctionEnded(auctionEndDate); 
            auctionEnded = true;
        } 
    }

    function finalizeAuctionByOwner() external onlyOwner {
        auctionEndDate = block.timestamp;
        auctionEnded = true;
        emit AuctionEnded(auctionEndDate);
    }

    function checkAuctionDates() external view returns (uint256, uint256) {
        return (auctionStartDate, auctionEndDate); 
    }

}

