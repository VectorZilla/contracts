pragma solidity ^0.4.18;

import "./math/SafeMath.sol";
import "./VZToken.sol";
import "./ownership/Ownable.sol";
import "./Pausable.sol";
import "./HasNoTokens.sol";


contract VZTPresale is Ownable, Pausable, HasNoTokens {

    using SafeMath for uint256;

    string public constant NAME = "VectorZilla Public Presale";
    string public constant VERSION = "0.5";

    VZToken token;

    // this multi-sig address will be replaced on production:
    address public constant VZT_WALLET = 0x4D9B157E1c2ed052560304ce10E81ec67AEAbbdF;

    uint256 public startDate = 1515974400;                                          // January 15, 2018 5:30 AM UTC
    uint256 public endDate = 1517788800;                                            // Febuary 5, 2018 5:30 AM UTC
    uint256 public weiRaised = 0;                                                   // total amount of Ether raised in wei
    uint256 public purchaserCount = 0;                                              // total number of purchasers purchased VZT
    uint256 public tokensSold = 0;                                                  // total number of VZT tokens sold
    uint256 public numWhitelisted = 0;                                              // total number whitelisted

    /* if the minimum funding goal in wei is not reached, purchasers may withdraw their funds */
    uint256 public constant MIN_FUNDING_GOAL = 200 * 10 ** 18;

    uint256 public constant PRESALE_TOKEN_SOFT_CAP = 1875000 * 10 ** 18;              // presale ends 48 hours after soft cap of 1,875,000 VZT is reached
    uint256 public constant PRESALE_RATE = 1250;                                    // presale price is 1 ETH to 1,250 VZT
    uint256 public constant SOFTCAP_RATE = 1150;                                    // presale price becomes 1 ETH to 1,150 VZT after softcap is reached
    uint256 public constant PRESALE_TOKEN_HARD_CAP = 5900000 * 10 ** 18;              // presale token hardcap
    uint256 public constant MIN_PURCHASE = 0.25 * 10 ** 17;                           // minimum purchase is 0.25 ETH to make the gas worthwhile
    uint256 public constant MIN_VZT_PURCHASE = 1150 * 10 ** 18;                        // minimum token purchase is 100 or 0.1 ETH


    bool public isFinalized = false;                                                // it becomes true when token sale is completed
    bool public publicSoftCapReached = false;                                       // it becomes true when public softcap is reached

    /** the amount of ETH in wei each address has purchased in this crowdsale */
    mapping(address => uint256) public purchasedAmountOf;

    /** the amount of tokens this crowdsale has credited for each purchaser address */
    mapping(address => uint256) public tokenAmountOf;

    // purchaser wallets
    address[] public purchasers;

    // list of addresses that can purchase
    mapping(address => bool) public whitelist;

    /**
    * event for token purchase logging
    * @param purchaser who paid for the tokens
    * @param beneficiary who got the tokens
    * @param value weis paid for purchase
    * @param amount amount of tokens purchased
    */
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    // event logging for token sale finalized
    event Finalized();
    // event logging for softcap reached
    event SoftCapReached();
    // event logging for funds transfered to VectorZilla multi-sig wallet
    event FundsTransferred();
    // event logging for each individual refunded amount
    event Refunded(address indexed beneficiary, uint256 weiAmount);

    /*
        Constructor to initialize everything.
    */
    function VZTPresale(address _token, address _owner) public {
        require(_token != address(0));
        require(_owner != address(0));
        token = VZToken(_token);
        // default owner
        owner = _owner;
        // maximum tokens to be sold in presale
        tokenAmountOf[owner] = PRESALE_TOKEN_HARD_CAP;
        

    }

    /*
       default function to buy tokens.
    */
    function() payable public whenNotPaused {
        // stop if no more token is allocated for sale
        require(isPresale());
        // stop if address not valid
        require(!hasSoldOut());
        // stop if the purchase is too small
        require(msg.sender != address(0));
        // no purchase unless whitelisted
        require(msg.value >= MIN_PURCHASE);
        // do public presale
        require(isWhitelisted(msg.sender));
        purchasePresale(msg.sender, msg.value);
    }

    function setDates(uint256 newStartDate, uint256 newEndDate) public onlyOwner {
        startDate = newStartDate;
        endDate = newEndDate;
    }

    function setTokenContract(address _token) external onlyOwner {
        require(token != address(0));
        token = VZToken(_token);

    }

    /*
        add the ether address to whitelist to enable purchase of token.
    */
    function addToWhitelist(address buyer) external onlyOwner {
        require(buyer != address(0));

        if (!isWhitelisted(buyer)) {
            whitelist[buyer] = true;
            numWhitelisted += 1;
        }
    }

    /*
        remove the ether address from whitelist in case a mistake was made.
    */
    function delFrWhitelist(address buyer) public onlyOwner {
        // Valid address
        require(buyer != address(0));
        // No purchase yet.
        require(purchasedAmountOf[buyer] <= 0);
        if (isWhitelisted(buyer)) {
            delete whitelist[buyer];
            numWhitelisted -= 1;
        }
    }

    // return true if buyer is whitelisted
    function isWhitelisted(address buyer) public view returns (bool) {
        return whitelist[buyer];
    }

    function purchasePresale(address buyer, uint256 value) internal {
        uint256 tokens = 0;
        // still under soft cap
        if (!publicSoftCapReached) {
            // 1 ETH for 1,250 VZT
            tokens = value * PRESALE_RATE;
            // get less if over softcap
            if (tokensSold + tokens > PRESALE_TOKEN_SOFT_CAP) {
                uint256 availablePresaleTokens = PRESALE_TOKEN_SOFT_CAP - tokensSold;
                uint256 softCapTokens = (value - (availablePresaleTokens / PRESALE_RATE)) * SOFTCAP_RATE;
                tokens = availablePresaleTokens + softCapTokens;
                // process presale at 1 ETH to 1,150 VZT
                processSale(buyer, value, tokens, SOFTCAP_RATE);
                // public soft cap has been reached
                publicSoftCapReached = true;
                // signal the event for communication
                SoftCapReached();
            } else {
                // process presale @PRESALE_RATE
                processSale(buyer, value, tokens, PRESALE_RATE);
            }
        } else {
            // 1 ETH to 1,150 VZT
            tokens = value * SOFTCAP_RATE;
            // process presale at 1 ETH to 1,150 VZT
            processSale(buyer, value, tokens, SOFTCAP_RATE);
        }
    }

    /*
        process sale at determined price.
    */
    function processSale(address buyer, uint256 value, uint256 vzt, uint256 vztRate) internal {

        uint256 vztOver = 0;
        uint256 excessEthInWei = 0;
        uint256 paidValue = value;
        uint256 purchasedVzt = vzt;

        if (tokensSold + purchasedVzt > PRESALE_TOKEN_HARD_CAP) {// if maximum is exceeded
            // find overage
            vztOver = tokensSold + purchasedVzt - PRESALE_TOKEN_HARD_CAP;
            // overage ETH to refund
            excessEthInWei = vztOver / vztRate;
            // adjust tokens purchased
            purchasedVzt = purchasedVzt - vztOver;
            // adjust Ether paid
            paidValue = paidValue - excessEthInWei;
        }
        if (tokenAmountOf[buyer] == 0) {
            // count new purchasers
            purchaserCount++;
            purchasers.push(buyer);
        }
        // deduct VZT from Vectorzilla account
        tokenAmountOf[owner] = tokenAmountOf[owner].sub(purchasedVzt);
        // record VZT on purchaser account
        tokenAmountOf[buyer] = tokenAmountOf[buyer].add(purchasedVzt);
        // record ETH paid
        purchasedAmountOf[buyer] = purchasedAmountOf[buyer].add(paidValue);
        // total ETH raised
        weiRaised += paidValue;
        // total VZT sold
        tokensSold += purchasedVzt;
        // signal the event for communication
        TokenPurchase(buyer, buyer, paidValue, purchasedVzt);
        // transfer must be done at the end after all states are updated to prevent reentrancy attack.
        if (excessEthInWei > 0) {
            // refund overage ETH
            buyer.transfer(excessEthInWei);
            // signal the event for communication
            Refunded(buyer, excessEthInWei);
        }
    }

   /*
       default function to buy tokens.
    */
    function payableInFiatEth(address buyer, uint256 value) external onlyOwner {
        require(isPresale());
        // stop if no more token is allocated for sale
        require(!hasSoldOut());
        // stop if address not valid
        require(buyer != address(0));
        // stop if the purchase is too small
        require(value >= MIN_PURCHASE);
        // no purchase unless whitelisted
        require(isWhitelisted(buyer));
        // do public presale
        purchasePresale(buyer, value);
    }


    /*
        Check to see if this is public presale.
    */
    function isPresale() public view returns (bool) {
        return !isFinalized && now >= startDate && now <= endDate;
    }

    /*
        check if allocated has sold out.
    */
    function hasSoldOut() public view returns (bool) {
        return PRESALE_TOKEN_HARD_CAP - tokensSold < MIN_VZT_PURCHASE;
    }

    /*
        Check to see if the crowdsale end date has passed or if all tokens allocated for sale has been purchased.
    */
    function hasEnded() public view returns (bool) {
        return now > endDate || (PRESALE_TOKEN_HARD_CAP - tokensSold < MIN_VZT_PURCHASE);
    }

    /*
        Determine if the minimum goal in wei has been reached.
    */
    function isMinimumGoalReached() public view returns (bool) {
        return weiRaised >= MIN_FUNDING_GOAL;
    }

    /*
        Called after crowdsale ends, to do some extra finalization work.
    */
    function finalize() public onlyOwner {
        require(!isFinalized);
        // do nothing if finalized
        require(hasEnded());
        // crowdsale must have ended
        if (isMinimumGoalReached()) {
            VZT_WALLET.transfer(this.balance);
            // transfer to VectorZilla multisig wallet
            FundsTransferred();
            // signal the event for communication
        }
        isFinalized = true;
        // mark as finalized
        Finalized();
        // signal the event for communication
    }

    /*
        purchaser requesting a refund if minimum goal not reached.
    */
    function claimRefund() external {
        require(isFinalized && !isMinimumGoalReached());
        // cannot refund unless authorized
        uint256 depositedValue = purchasedAmountOf[msg.sender];
        // ETH to refund
        purchasedAmountOf[msg.sender] = 0;
        // assume all refunded
        // transfer must be called only after purchasedAmountOf is updated to prevent reentrancy attack.
        msg.sender.transfer(depositedValue);
        // refund all ETH
        Refunded(msg.sender, depositedValue);
        // signal the event for communication
    }

    /*
      send refund to purchaser if minimum goal not reached.
  */
    function sendRefund(address buyer) external onlyOwner {
        // cannot refund unless authorized
        require(isFinalized && !isMinimumGoalReached());
        // ETH to refund
        uint256 depositedValue = purchasedAmountOf[buyer];
        // assume all refunded
        purchasedAmountOf[buyer] = 0;
        // transfer must be called only after purchasedAmountOf is updated to prevent reentrancy attack.
        // refund all ETH
        buyer.transfer(depositedValue);
        // signal the event for communication
        Refunded(buyer, depositedValue);
    }

    /*
        For the convenience of crowdsale interface to find current discount tier.
    */
    function getTier() public view returns (uint256) {
        // Assume presale top tier discount
        uint256 tier = 1;
        if (now >= startDate && now < endDate && getSoftCapReached()) {
            // tier 2 discount
            tier = 2;
        }
        return tier;
    }

    /*
        For the convenience of crowdsale interface to present status info.
    */
    function getSoftCapReached() public view returns (bool) {
        return publicSoftCapReached;
    }

    /*
        For the convenience of crowdsale interface to present status info.
    */
    function getPresaleStatus() public view returns (uint256[3]) {
        // 0 - presale not started
        // 1 - presale started
        // 2 - presale ended
        if (now < startDate)
            return ([0, startDate, endDate]);
        else if (now <= endDate && !hasEnded())
            return ([1, startDate, endDate]);
        else
            return ([2, startDate, endDate]);
    }
}