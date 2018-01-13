pragma solidity ^0.4.18;

import './math/SafeMath.sol';
import "./VZToken.sol";
import "./ownership/Ownable.sol";
import "./HasNoTokens.sol";
import "./VZTPresale.sol";

contract VZTPresaleDist is Ownable, HasNoTokens {
    using SafeMath for uint256;

    string public name = "VectorZilla token distribution";
    string public version = "0.3";

    VZToken             token;
    VZTPresale          preSale;

    // total number of purchasers purchased VZT
    uint256 public purchaserCount = 0;
    // total number of purchasers received purchased VZT + bonus
    uint256 public purchaserDistCount = 0;
    uint256 public tokensSold = 0;
    uint256 public minVztPurchase = 0;
    uint256 public tokenHardCap = 0;
    /** this becomes true when crowdsale has distributed purchased tokens with bonus for each purchaser address */
    mapping (address => bool) public tokenDistributed;

    // event logging for each individual distributed token + bonus
    event TokenDistributed(address indexed purchaser, uint256 tokenAmt);


    /*
        Constructor to initialize everything.
    */
    function VZTPresaleDist (address _presale, address _token, address _owner) public {
        if (_owner == address(0)) {
            _owner = msg.sender;
        }
        require(_presale != address(0));
        require(_owner != address(0));
        token = VZToken(_token);
        // default owner
        owner = _owner;
        preSale = VZTPresale(_presale);
        // initialize to all purchaser count
        purchaserCount = preSale.purchaserCount();
        // initialize token sold from crowd sale
        tokensSold = preSale.tokensSold();
        minVztPurchase = preSale.MIN_VZT_PURCHASE();
        tokenHardCap = preSale.PRESALE_TOKEN_HARD_CAP();
    }

    function setTokenContract(address _token) external onlyOwner {
        require(token != address(0));
        token = VZToken(_token);
    }

    /*
        Distribute tokens purchased with bonus.
    */
    function distributeTokensFor(address purchaser) external onlyOwner {
        require(token != address(0));
        require(preSale.isFinalized());
        require(preSale.isMinimumGoalReached());
        require(!tokenDistributed[purchaser]);
        // token + bonus distributed
        tokenDistributed[purchaser] = true;
        uint256 tokenPurchased = preSale.tokenAmountOf(purchaser);
         // one more purchaser received token + bonus
        purchaserDistCount++;
        // transfer the purchased tokens + bonus
        token.transfer(purchaser, tokenPurchased);
        // signal the event for communication
        TokenDistributed(purchaser, tokenPurchased);
    }
}