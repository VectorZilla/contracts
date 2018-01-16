pragma solidity ^0.4.18;

import "./StandardToken.sol";
import "./ownership/Ownable.sol";

contract VZToken is StandardToken, Ownable {

    /* metadata */
    string public constant name = "VectorZilla Token";
    string public constant symbol = "VZT";
    string public constant version = "0.9";
    uint8  public constant decimals = 18;

    /* all accounts in wei */
    uint256 public constant INITIAL_SUPPLY = 100000000 * 10**18;
    uint256 public constant VECTORZILLA_RESERVE_VZT = 25000000 * 10**18;

    // this address will be replaced on production:
    address public constant VECTORZILLA_RESERVE = 0x76f458A8aBe327D79040931AC97f74662EF3CaD0;

    // list of addresses that have transfer restriction.
    mapping (address => bool) public accreditedList;
    mapping(address => uint256) public accreditedDates;
    uint256 public numOfAccredited = 0;
    uint256 public defaultAccreditedDate = 1703543589;                       // Assume many years
    // Flag that determines if the token is transferable or not.
    bool public transfersEnabled = true;

    //log event whenever withdrawal from this contract address happens
    event Withdraw(address indexed from, address indexed to, uint256 value);

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
        // do nothing if less than allowed minimum but do not fail
        require(_to != address(0));
        require(_value > 0); 
        address _from = msg.sender;
        if (isContract(_from) && tx.origin == owner) {
            _from = owner;
        }
        // Check if token transfer is allowed for msg.sender
        require(canTransferTokens(_from));
        _transfer(_from, _to, _value);
        return true;
    }

      /**
   * @dev Transfer tokens from one address to another
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint256 the amount of tokens to be transferred
   */
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        require(canTransferTokens(_from));
        return super.transferFrom(_from, _to, _value);
  }
    /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
   *
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param _spender The address which will spend the funds.
   * @param _value The amount of tokens to be spent.
   */
  function approve(address _spender, uint256 _value) public returns (bool) {
      return super.approve(_spender, _value);
  }
    /// @notice Enables token holders to transfer their tokens freely if true
    /// @param _transfersEnabled True if transfers are allowed in the clone
    function enableTransfers(bool _transfersEnabled) external onlyOwner {
        transfersEnabled = _transfersEnabled;
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
    function removeFromAccreditedList(address _addr) external onlyOwner {
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
    function getAccreditedDateFor(address _addr) public view returns (uint256) {
        require(_addr != address(0));
        return accreditedDates[_addr];
    }

     /*
        Allow changes to accredited date.
    */
    function setAccreditedDateFor(address _addr, uint256 newAccreditedDate) public onlyOwner {
        require(_addr != address(0));
        require(accreditedList[_addr]);
        require(newAccreditedDate > now);
        accreditedDates[_addr] = newAccreditedDate;
    }

    /*
        Set default accredited date.
    */
    function setAccreditedDate(uint256 newAccreditedDate) public onlyOwner {
        require(newAccreditedDate > now);
        defaultAccreditedDate = newAccreditedDate;
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
    function canTransferTokens(address _addr) internal view returns (bool) {
        if (accreditedList[_addr]) {
            return now >= accreditedDates[_addr];
        } else {
            return transfersEnabled;
        }
    }

    /// @notice This method can be used by the controller to extract mistakenly
    ///  sent tokens to this contract.
    /// @param _token The address of the token contract that you want to recover
    ///  set to 0 in case you want to extract ether.
    function claimTokens(address _token) external onlyOwner {
        if (_token == 0x0) {
            owner.transfer(this.balance);
            return;
        }
        StandardToken token = StandardToken(_token);
        uint balance = token.balanceOf(this);
        token.transfer(owner, balance);
        // signal the event for communication only it is meaningful
        Withdraw(this, owner, balance);
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

        /**
     * Internal transfer, only can be called by this contract
     */
    function _transfer(address _from, address _to, uint _value) internal {
        // Prevent transfer to 0x0 address. Use burn() instead
        require(_to != 0x0);
        // Check if the sender has enough
        require(balances[_from] >= _value);
        // Check for overflows
        require(balances[_to] + _value > balances[_to]);
        // Save this for an assertion in the future
        uint256 previousBalances = balances[_from] + balances[_to];
        // Subtract from the sender
        balances[_from] -= _value;
        // Add the same to the recipient
        balances[_to] += _value;
        Transfer(_from, _to, _value);
        // Asserts are used to use static analysis to find bugs in your code. They should never fail
        assert(balances[_from] + balances[_to] == previousBalances);
    }
}