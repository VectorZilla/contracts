pragma solidity ^0.4.18;

import "./StandardToken.sol";
import "./ownership/Ownable.sol";


contract VZToken is StandardToken, Ownable {

    /* metadata */
    string public constant name = "VectorZilla Token";
    string public constant symbol = "VZT";
    string public constant version = "0.5";
    uint8  public constant decimals = 18;

    /* all accounts in wei */
    uint256 public constant INITIAL_SUPPLY = 100000000 * 10**18;
    uint256 public constant VECTORZILLA_RESERVE_VZT = 25000000 * 10**18;

    // this address will be replaced on production:
    address public constant VECTORZILLA_RESERVE = 0x76f458A8aBe327D79040931AC97f74662EF3CaD0;

    /* minimum VZT token to be transferred to make the gas worthwhile (avoid micro transfer),
       cannot be higher than minimal subscribed amount in crowd sale. */
    uint256 public token4Gas = 1*10**18;
    // gas in wei to reimburse must be the lowest minimum 0.6Gwei * 80000 gas limit.
    uint256 public gas4Token = 80000*0.6*10**9;
    // minimum wei required in an account to perform an action (avg gas price 4Gwei * avg gas limit 80000).
    uint256 public minGas4Accts = 80000*4*10**9;

    // list of addresses that have transfer restriction.
    mapping (address => bool) public accreditedList;
    mapping(address => uint256) public accreditedDates;
    uint256 public numOfAccredited = 0;
    uint256 public defaultAccreditedDate = 1703543589;                       // Assume many years


    event Withdraw(address indexed from, address indexed to, uint256 value);
    event GasRebateFailed(address indexed to, uint256 value);

    /*
        Contructor that distributes initial supply between
        owner and vzt reserve.
    */
    function VZToken(address _owner) public {
        require(_owner != address(0));
        totalSupply = INITIAL_SUPPLY;
        balances[_owner] = INITIAL_SUPPLY - VECTORZILLA_RESERVE_VZT;
        balances[VECTORZILLA_RESERVE] = VECTORZILLA_RESERVE_VZT;
        owner = _owner;
    }

    /**
    * @dev transfer token for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint256 _value) public returns (bool) {
        // Check if token transfer is allowed for msg.sender
        require(canTransferTokens());
        // do nothing if less than allowed minimum but do not fail
        require(_value > 0 && _value >= token4Gas);
        // insufficient token balance would revert here inside safemath
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        Transfer(msg.sender, _to, _value);
        /* Keep a minimum balance of gas in all sender accounts.
           It would not be executed if the account has enough ETH for next action. */
        if (this.balance > gas4Token && msg.sender.balance < minGas4Accts) {
            /* reimburse gas in ETH to keep a minimal balance for next
               transaction, use send instead of transfer thus ignore
               failed rebate(not enough ether to rebate etc.). */
            if (!msg.sender.send(gas4Token)) {
                GasRebateFailed(msg.sender,gas4Token);
            }
        }
        return true;
    }

    /*
        add the ether address to accredited list to put in transfer restrction.
    */
    function addToAccreditedList(address _addr) external onlyOwner {
        require(_addr != address(0));
        require(!accreditedList[_addr]);
        accreditedList[_addr] = true;
        accreditedDates[_addr] = defaultAccreditedDate;
        numOfAccredited += 1;
    }

    /*
        remove the ether address from accredited list to remove transfer restriction.
    */
    function delFrAccreditedList(address _addr) external onlyOwner {
        require(accreditedList[_addr]);

        delete accreditedList[_addr];
        delete accreditedDates[_addr];
        numOfAccredited -= 1;
    }

    /*
        return true if _addr is an accredited
    */
    function isAccreditedlisted(address _addr) public view returns (bool) {
        return accreditedList[_addr];
    }

    /*
        return accredited date date of _addr is an accredited
    */
    function getAccreditedDateFor(address buyer) public view returns (uint256) {
        return accreditedDates[buyer];
    }

     /*
        Allow changes to accredited date.
    */
    function setAccreditedDateFor(address _addr, uint256 newAccreditedDate) public onlyOwner {
        require(_addr != address(0));
        require(accreditedList[_addr]);
        accreditedDates[_addr] = newAccreditedDate;
    }

    /*
        Set default accredited date.
    */
    function setAccreditedDate(uint256 newAccreditedDate) public onlyOwner {
        defaultAccreditedDate = newAccreditedDate;
    }

    /* When necessary, adjust minimum VZT to transfer to make the gas worthwhile */
    function setToken4Gas(uint newVZTAmount) public onlyOwner {
        // Upper bound is not necessary.
        require(newVZTAmount > 0);
        token4Gas = newVZTAmount;
    }

    /*
        Only when necessary such as gas price change, adjust the gas to be reimbursed
         on every transfer when sender account below minimum 
    */
    function setGas4Token(uint newGasInWei) public onlyOwner {
        // must be less than a reasonable gas value
        require(newGasInWei > 0 && newGasInWei <= 840000*10**9);
        gas4Token = newGasInWei;
    }

    /*
        When necessary, adjust the minimum wei required in an account before an
        reimibusement of fee is triggerred 
    */
    function setMinGas4Accts(uint minBalanceInWei) public onlyOwner {
        // must be less than a reasonable gas value
        require(minBalanceInWei > 0 && minBalanceInWei <= 840000*10**9);
        minGas4Accts = minBalanceInWei;
    }

    /*
        This unnamed function is called whenever the owner send Ether to fund the gas
        fees and gas reimbursement 
    */
    function() payable public onlyOwner {
    }

    /* Owner withdrawal for excessive gas fees deposited */
    function withdrawToOwner (uint256 weiAmt) public onlyOwner {
        // do not allow zero transfer
        require(weiAmt > 0);
        msg.sender.transfer(weiAmt);
        // signal the event for communication only it is meaningful
        Withdraw(this, msg.sender, weiAmt);
    }

    /* below are internal functions */
    /*
        VectorZilla and Accredited folks can only transfer tokens after accredited date.
    */
    function canTransferTokens() internal view returns (bool) {
        if (accreditedList[msg.sender]) {
            return now >= accreditedDates[msg.sender];
        } else {
            return true;
        }
    }

}