pragma solidity ^0.4.18;

import "./math/SafeMath.sol";
import "./VZToken.sol";
import "./ownership/Ownable.sol";
import "./Pausable.sol";
import "./HasNoTokens.sol";


contract VZTPresale is Ownable, Pausable, HasNoTokens {


    using SafeMath for uint256;

    string public constant name = "VectorZilla Public Presale";  // solium-disable-line uppercase
    string public constant version = "1.0"; // solium-disable-line uppercase

    VZToken token;

    // this multi-sig address will be replaced on production:
    address public constant VZT_WALLET = 0x4D9B157E1c2ed052560304ce10E81ec67AEAbbdF;
    /* if the minimum funding goal in wei is not reached, buyers may withdraw their funds */
    uint256 public constant MIN_FUNDING_GOAL = 200 * 10 ** 18;
    uint256 public constant PRESALE_TOKEN_SOFT_CAP = 1875000 * 10 ** 18;    // presale soft cap of 1,875,000 VZT
    uint256 public constant PRESALE_RATE = 1250;                            // presale price is 1 ETH to 1,250 VZT
    uint256 public constant SOFTCAP_RATE = 1150;                            // presale price becomes 1 ETH to 1,150 VZT after softcap is reached
    uint256 public constant PRESALE_TOKEN_HARD_CAP = 5900000 * 10 ** 18;    // presale token hardcap
    uint256 public constant MAX_GAS_PRICE = 50000000000;

    uint256 public minimumPurchaseLimit = 0.1 * 10 ** 18;                      // minimum purchase is 0.1 ETH to make the gas worthwhile
    uint256 public startDate = 1516001400;                            // January 15, 2018 7:30 AM UTC
    uint256 public endDate = 1517815800;                              // Febuary 5, 2018 7:30 AM UTC
    uint256 public totalCollected = 0;                                // total amount of Ether raised in wei
    uint256 public tokensSold = 0;                                    // total number of VZT tokens sold
    uint256 public totalDistributed = 0;                              // total number of VZT tokens distributed once finalised
    uint256 public numWhitelisted = 0;                                // total number whitelisted

    struct PurchaseLog {
        uint256 ethValue;
        uint256 vztValue;
        bool kycApproved;
        bool tokensDistributed;
        bool paidFiat;
        uint256 lastPurchaseTime;
        uint256 lastDistributionTime;
    }

    //purchase log that captures
    mapping (address => PurchaseLog) public purchaseLog;
    //capture refunds
    mapping (address => bool) public refundLog;
    //capture buyers in array, this is for quickly looking up from DAPP
    address[] public buyers;
    uint256 public buyerCount = 0;                                              // total number of buyers purchased VZT

    bool public isFinalized = false;                                        // it becomes true when token sale is completed
    bool public publicSoftCapReached = false;                               // it becomes true when public softcap is reached

    // list of addresses that can purchase
    mapping(address => bool) public whitelist;

    // event logging for token purchase
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    // event logging for token sale finalized
    event Finalized();
    // event logging for softcap reached
    event SoftCapReached();
    // event logging for funds transfered to VectorZilla multi-sig wallet
    event FundsTransferred();
    // event logging for each individual refunded amount
    event Refunded(address indexed beneficiary, uint256 weiAmount);
    // event logging for each individual distributed token + bonus
    event TokenDistributed(address indexed purchaser, uint256 tokenAmt);


    /*
        Constructor to initialize everything.
    */
    function VZTPresale(address _token, address _owner) public {
        require(_token != address(0));
        require(_owner != address(0));
        token = VZToken(_token);
        // default owner
        owner = _owner;
    }

    /*
       default function to buy tokens.
    */

    function() payable public whenNotPaused {
        doPayment(msg.sender);
    }

    /*
       allows owner to register token purchases done via fiat-eth (or equivalent currency)
    */
    function payableInFiatEth(address buyer, uint256 value) external onlyOwner {
        purchaseLog[buyer].paidFiat = true;
        // do public presale
        purchasePresale(buyer, value);
    }

    function setTokenContract(address _token) external onlyOwner {
        require(token != address(0));
        token = VZToken(_token);

    }

    /**
    * add address to whitelist
    * @param _addr wallet address to be added to whitelist
    */
    function addToWhitelist(address _addr) public onlyOwner returns (bool) {
        require(_addr != address(0));
        if (!whitelist[_addr]) {
            whitelist[_addr] = true;
            numWhitelisted++;
        }
        purchaseLog[_addr].kycApproved = true;
        return true;
    }

     /**
      * add address to whitelist
      * @param _addresses wallet addresses to be whitelisted
      */
    function addManyToWhitelist(address[] _addresses) 
        external 
        onlyOwner 
        returns (bool) 
        {
        require(_addresses.length <= 50);
        uint idx = 0;
        uint len = _addresses.length;
        for (; idx < len; idx++) {
            address _addr = _addresses[idx];
            addToWhitelist(_addr);
        }
        return true;
    }
    /**
     * remove address from whitelist
     * @param _addr wallet address to be removed from whitelist
     */
     function removeFomWhitelist(address _addr) public onlyOwner returns (bool) {
         require(_addr != address(0));
         require(whitelist[_addr]);
        delete whitelist[_addr];
        purchaseLog[_addr].kycApproved = false;
        numWhitelisted--;
        return true;
     }

    /*
        Send Tokens tokens to a buyer:
        - and KYC is approved
    */
    function sendTokens(address _user) public onlyOwner returns (bool) {
        require(_user != address(0));
        require(_user != address(this));
        require(purchaseLog[_user].kycApproved);
        require(purchaseLog[_user].vztValue > 0);
        require(!purchaseLog[_user].tokensDistributed);
        require(!refundLog[_user]);
        purchaseLog[_user].tokensDistributed = true;
        purchaseLog[_user].lastDistributionTime = now;
        totalDistributed++;
        token.sendToken(_user, purchaseLog[_user].vztValue);
        TokenDistributed(_user, purchaseLog[_user].vztValue);
        return true;
    }

    /*
        Refund ethers to buyer if KYC couldn't/wasn't verified.
    */
    function refundEthIfKYCNotVerified(address _user) public onlyOwner returns (bool) {
        if (!purchaseLog[_user].kycApproved) {
            return doRefund(_user);
        }
        return false;
    }

    /*

    /*
        return true if buyer is whitelisted
    */
    function isWhitelisted(address buyer) public view returns (bool) {
        return whitelist[buyer];
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
        return PRESALE_TOKEN_HARD_CAP - tokensSold < getMinimumPurchaseVZTLimit();
    }

    /*
        Check to see if the presale end date has passed or if all tokens allocated
        for sale has been purchased.
    */
    function hasEnded() public view returns (bool) {
        return now > endDate || hasSoldOut();
    }

    /*
        Determine if the minimum goal in wei has been reached.
    */
    function isMinimumGoalReached() public view returns (bool) {
        return totalCollected >= MIN_FUNDING_GOAL;
    }

    /*
        For the convenience of presale interface to present status info.
    */
    function getSoftCapReached() public view returns (bool) {
        return publicSoftCapReached;
    }

    function setMinimumPurchaseEtherLimit(uint256 newMinimumPurchaseLimit) external onlyOwner {
        require(newMinimumPurchaseLimit > 0);
        minimumPurchaseLimit = newMinimumPurchaseLimit;
    }
    /*
        For the convenience of presale interface to find current tier price.
    */

    function getMinimumPurchaseVZTLimit() public view returns (uint256) {
        if (getTier() == 1) {
            return minimumPurchaseLimit.mul(PRESALE_RATE); //1250VZT/ether
        } else if (getTier() == 2) {
            return minimumPurchaseLimit.mul(SOFTCAP_RATE); //1150VZT/ether
        }
        return minimumPurchaseLimit.mul(1000); //base price
    }

    /*
        For the convenience of presale interface to find current discount tier.
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
        For the convenience of presale interface to present status info.
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

    /*
        Called after presale ends, to do some extra finalization work.
    */
    function finalize() public onlyOwner {
        // do nothing if finalized
        require(!isFinalized);
        // presale must have ended
        require(hasEnded());

        if (isMinimumGoalReached()) {
            // transfer to VectorZilla multisig wallet
            VZT_WALLET.transfer(this.balance);
            // signal the event for communication
            FundsTransferred();
        }
        // mark as finalized
        isFinalized = true;
        // signal the event for communication
        Finalized();
    }


    /**
     * @notice `proxyPayment()` allows the caller to send ether to the VZTPresale
     * and have the tokens created in an address of their choosing
     * @param buyer The address that will hold the newly created tokens
     */
    function proxyPayment(address buyer) 
    payable 
    public
    whenNotPaused 
    returns(bool success) 
    {
        return doPayment(buyer);
    }

    /*
        Just in case we need to tweak pre-sale dates
    */
    function setDates(uint256 newStartDate, uint256 newEndDate) public onlyOwner {
        require(newEndDate >= newStartDate);
        startDate = newStartDate;
        endDate = newEndDate;
    }


    // @dev `doPayment()` is an internal function that sends the ether that this
    //  contract receives to the `vault` and creates tokens in the address of the
    //  `buyer` assuming the VZTPresale is still accepting funds
    //  @param buyer The address that will hold the newly created tokens
    // @return True if payment is processed successfully
    function doPayment(address buyer) internal returns(bool success) {
        require(tx.gasprice <= MAX_GAS_PRICE);
        // Antispam
        // do not allow contracts to game the system
        require(buyer != address(0));
        require(!isContract(buyer));
        // limit the amount of contributions to once per 100 blocks
        //require(getBlockNumber().sub(lastCallBlock[msg.sender]) >= maxCallFrequency);
        //lastCallBlock[msg.sender] = getBlockNumber();

        if (msg.sender != owner) {
            // stop if presale is over
            require(isPresale());
            // stop if no more token is allocated for sale
            require(!hasSoldOut());
            require(msg.value >= minimumPurchaseLimit);
        }
        require(msg.value > 0);
        purchasePresale(buyer, msg.value);
        return true;
    }

    /// @dev Internal function to determine if an address is a contract
    /// @param _addr The address being queried
    /// @return True if `_addr` is a contract
    function isContract(address _addr) constant internal returns (bool) {
        if (_addr == 0) {
            return false;
        }
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    /// @dev Internal function to process sale
    /// @param buyer The buyer address
    /// @param value  The value of ether paid
    function purchasePresale(address buyer, uint256 value) internal {
         require(value >= minimumPurchaseLimit);
         require(buyer != address(0));
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
        require(buyer != address(0));
        require(vzt > 0);
        require(vztRate > 0);
        require(value > 0);

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

        /* To quick lookup list of buyers (pending token, kyc, or even refunded)
            we are keeping an array of buyers. There might be duplicate entries when
            a buyer gets refund (incomplete kyc, or requested), and then again contributes.
        */
        if (purchaseLog[buyer].vztValue == 0) {
            buyers.push(buyer);
            buyerCount++;
        }

        //if not whitelisted, mark kyc pending
        if (!isWhitelisted(buyer)) {
            purchaseLog[buyer].kycApproved = false;
        }
        //reset refund status in refundLog
        refundLog[buyer] = false;

         // record purchase in purchaseLog
        purchaseLog[buyer].vztValue = SafeMath.add(purchaseLog[buyer].vztValue, purchasedVzt);
        purchaseLog[buyer].ethValue = SafeMath.add(purchaseLog[buyer].ethValue, paidValue);
        purchaseLog[buyer].lastPurchaseTime = now;


        // total Wei raised
        totalCollected += paidValue;
        // total VZT sold
        tokensSold += purchasedVzt;

        /*
            For event, log buyer and beneficiary properly
        */
        address beneficiary = buyer;
        if (beneficiary == msg.sender) {
            beneficiary = msg.sender;
        }
        // signal the event for communication
        TokenPurchase(buyer, beneficiary, paidValue, purchasedVzt);
        // transfer must be done at the end after all states are updated to prevent reentrancy attack.
        if (excessEthInWei > 0 && !purchaseLog[buyer].paidFiat) {
            // refund overage ETH
            buyer.transfer(excessEthInWei);
            // signal the event for communication
            Refunded(buyer, excessEthInWei);
        }
    }

    /*
        Distribute tokens to a buyer:
        - when minimum goal is reached
        - and KYC is approved
    */
    function distributeTokensFor(address buyer) external onlyOwner returns (bool) {
        require(isFinalized);
        require(hasEnded());
        if (isMinimumGoalReached()) {
            return sendTokens(buyer);
        }
        return false;
    }

    /*
        purchaser requesting a refund, only allowed when minimum goal not reached.
    */
    function claimRefund() external returns (bool) {
        return doRefund(msg.sender);
    }

    /*
      send refund to purchaser requesting a refund 
   */
    function sendRefund(address buyer) external onlyOwner returns (bool) {
        return doRefund(buyer);
    }

    /*
        Internal function to manage refunds 
    */
    function doRefund(address buyer) internal returns (bool) {
        require(tx.gasprice <= MAX_GAS_PRICE);
        require(buyer != address(0));
        require(!purchaseLog[buyer].paidFiat);
        if (msg.sender != owner) {
            // cannot refund unless authorized
            require(isFinalized && !isMinimumGoalReached());
        }
        require(purchaseLog[buyer].ethValue > 0);
        require(purchaseLog[buyer].vztValue > 0);
        require(!refundLog[buyer]);
        require(!purchaseLog[buyer].tokensDistributed);

        // ETH to refund
        uint256 depositedValue = purchaseLog[buyer].ethValue;
        //VZT to revert
        uint256 vztValue = purchaseLog[buyer].vztValue;
        // assume all refunded, should we even do this if
        // we are going to delete buyer from log?
        purchaseLog[buyer].ethValue = 0;
        purchaseLog[buyer].vztValue = 0;
        refundLog[buyer] = true;
        //delete from purchase log.
        //but we won't remove buyer from buyers array
        delete purchaseLog[buyer];
        //decrement global counters
        tokensSold = tokensSold.sub(vztValue);
        totalCollected = totalCollected.sub(depositedValue);

        // send must be called only after purchaseLog[buyer] is deleted to
        //prevent reentrancy attack.
        buyer.transfer(depositedValue);
        Refunded(buyer, depositedValue);
        return true;
    }

    function getBuyersList() external view returns (address[]) {
        return buyers;
    }

    /**
        * @dev Transfer all Ether held by the contract to the owner.
        * Emergency where we might need to recover
    */
    function reclaimEther() external onlyOwner {
        assert(owner.send(this.balance));
    }

}