// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Subasta {

    address private owner;
    uint256 internal auctionStartDate;
    uint256 internal auctionEndDate;
    uint256 public minBid;
    bool internal auctionEnded;
    
    constructor() {
        owner = msg.sender;
        auctionStartDate = block.timestamp; 
        auctionEndDate = auctionStartDate + 5 minutes;
        minBid = 1000 wei;
        auctionEnded = false;
        
    } 

    struct Offer {
        address offerer;
        uint256 value;
	} 
    
    Offer[] private offers;
    Offer private winner;

    event NewOffer(uint256 _value, address indexed _offerer, uint256 _auctionStartDate, uint256 _auctionEndDate);
    event AuctionEnded(uint256 _auctionEndDate);
    event NewPartialClaim(address indexed _offerer, uint256 _value);
    event NewClaim(address indexed _offerer, uint256 _value);

    mapping (address => uint256) internal pendingBalances;
    mapping (address => uint256) internal lastOfferPerAddress;


    modifier validateOffer(uint256 _value) {
        require(_value >= minBid && _value % minBid == 0, "Error: debe ser en valores multiplos de 1000 Wei."); 
        require(winner.value * 105 / 100 <= _value, "Error:La nueva oferta debe ser 5% mayor a la anterior.");
        require(msg.sender != winner.offerer, "Error: Tienes la ultima oferta de la subasta.");
        _; 
    }   
    modifier validateAuctionDates {
        require(block.timestamp > auctionStartDate, "Error: La subasta no ha comenzado."); 
        require(!auctionEnded, "Error: La subasta ya finalizo.");
        _;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Error: No es el propietario."); 
        _;
    }

    modifier notOwnerOnly {
        require(msg.sender != owner, "Error: El propietario no puede participar en la Subasta.");
        _;
    }

    modifier isAuctionEnd {
        require(auctionEnded, "Error: La Subasta aun no finaliza.");
        _;
    }

    function partialClaim() external notOwnerOnly  {
        endAuction();
        address _addr = msg.sender;
        uint256 _lastOffer = lastOfferPerAddress[msg.sender];
        uint256 _actualBalance = pendingBalances[msg.sender];
        uint256 _total = _actualBalance - _lastOffer;
        require(_lastOffer < _actualBalance, "Error: Solo puede retirar el ultimo deposito al final de la subasta y no siendo el ganador.");
        pendingBalances[_addr] = _lastOffer;
        (bool _result,) = _addr.call{value: _total}("");
        require(_result, "Error: No se pudo enviar los Ether.");
        emit NewPartialClaim(_addr, _total);
    }

    function totalClaim() external isAuctionEnd onlyOwner {
        address _addr;
        uint256 _total;
        
        for (uint256 i = 0; i < offers.length; i++ ) {
            if (offers[i].offerer == winner.offerer && pendingBalances[winner.offerer] > winner.value) {
                _total = pendingBalances[winner.offerer] - winner.value;
                _addr = winner.offerer;
                pendingBalances[winner.offerer] = 0;
            } else if (pendingBalances[offers[i].offerer]  > 0)  {
                _total = pendingBalances[offers[i].offerer];
                _addr = offers[i].offerer;
                pendingBalances[offers[i].offerer] = 0;
            }
            _total = _total * 98 / 100;

            (bool _result,) = _addr.call{value: _total}("");
            require(_result, "Error: No se pudo enviar los Ether.");  
            emit NewClaim(_addr, _total);   
        }
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
        }
    }

    function showWinner() external view isAuctionEnd returns(address, uint256) {
        return (winner.offerer,winner.value);    
    }   

    function showOffers () external view returns(Offer[] memory) {
        return offers;
    }

    function showBalance () external view onlyOwner returns(uint256) {
        return address(this).balance;
    }  

    function endAuction() internal {
        if (block.timestamp >= auctionEndDate){    
            emit AuctionEnded(auctionEndDate); 
            auctionEnded = true;
        } 
    }

}

