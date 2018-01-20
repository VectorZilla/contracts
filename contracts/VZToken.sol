pragma solidity ^0.4.18;

import "./StandardToken.sol";
import "./ownership/Ownable.sol";

/** This interfaces will be implemented by different VZT contracts in future*/
interface tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public; }

contract VZToken is StandardToken, Ownable {


    /* metadata */

    string public constant name = "VectorZilla Token"; // solium-disable-line uppercase
    string public constant symbol = "VZT"; // solium-disable-line uppercase
    string public constant version = "1.0"; // solium-disable-line uppercase
    uint8 public constant decimals = 18; // solium-disable-line uppercase

    /* all accounts in wei */

    uint256 public constant INITIAL_SUPPLY = 100000000 * 10 ** 18; //intial total supply
    uint256 public constant BURNABLE_UP_TO =  90000000 * 10 ** 18; //burnable up to 90% (90 million) of total supply
    uint256 public constant VECTORZILLA_RESERVE_VZT = 25000000 * 10 ** 18; //25 million - reserved tokens

    // Reserved tokens will be sent to this address. this address will be replaced on production:
    address public constant VECTORZILLA_RESERVE = 0x76f458A8aBe327D79040931AC97f74662EF3CaD0;

    // - tokenSaleContract receives the whole balance for distribution
    address public tokenSaleContract;

    /* Following stuff is to manage regulatory hurdles on who can and cannot use VZT token  */
    mapping (address => bool) public frozenAccount;
    event FrozenFunds(address target, bool frozen);


    /** Modifiers to be used all over the place **/

    modifier onlyOwnerAndContract() {
        require(msg.sender == owner || msg.sender == tokenSaleContract);
        _;
    }


    modifier onlyWhenValidAddress( address _addr ) {
        require(_addr != address(0x0));
        _;
    }

    modifier onlyWhenValidContractAddress(address _addr) {
        require(_addr != address(0x0));
        require(_addr != address(this));
        require(isContract(_addr));
        _;
    }

    modifier onlyWhenBurnable(uint256 _value) {
        require(totalSupply - _value >= INITIAL_SUPPLY - BURNABLE_UP_TO);
        _;
    }

    modifier onlyWhenNotFrozen(address _addr) {
        require(!frozenAccount[_addr]);
        _;
    }

    /** End of Modifier Definations */

    /** Events */

    event Burn(address indexed burner, uint256 value);
    event Finalized();
    //log event whenever withdrawal from this contract address happens
    event Withdraw(address indexed from, address indexed to, uint256 value);

    /*
        Contructor that distributes initial supply between
        owner and vzt reserve.
    */
    function VZToken(address _owner) public {
        require(_owner != address(0));
        totalSupply = INITIAL_SUPPLY;
        balances[_owner] = INITIAL_SUPPLY - VECTORZILLA_RESERVE_VZT; //75 millions tokens
        balances[VECTORZILLA_RESERVE] = VECTORZILLA_RESERVE_VZT; //25 millions
        owner = _owner;
    }

    /*
        This unnamed function is called whenever the owner send Ether to fund the gas
        fees and gas reimbursement.
    */
    function () payable public onlyOwner {}

    /**
     * @dev transfer `_value` token for a specified address
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     */
    function transfer(address _to, uint256 _value) 
        public
        onlyWhenValidAddress(_to)
        onlyWhenNotFrozen(msg.sender)
        onlyWhenNotFrozen(_to)
        returns(bool) {
        return super.transfer(_to, _value);
    }

    /**
     * @dev Transfer `_value` tokens from one address (`_from`) to another (`_to`)
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function transferFrom(address _from, address _to, uint256 _value) 
        public
        onlyWhenValidAddress(_to)
        onlyWhenValidAddress(_from)
        onlyWhenNotFrozen(_from)
        onlyWhenNotFrozen(_to)
        returns(bool) {
        return super.transferFrom(_from, _to, _value);
    }

    /**
     * @dev Burns a specific (`_value`) amount of tokens.
     * @param _value uint256 The amount of token to be burned.
     */
    function burn(uint256 _value)
        public
        onlyWhenBurnable(_value)
        onlyWhenNotFrozen(msg.sender)
        returns (bool) {
        require(_value <= balances[msg.sender]);
      // no need to require value <= totalSupply, since that would imply the
      // sender's balance is greater than the totalSupply, which *should* be an assertion failure
        address burner = msg.sender;
        balances[burner] = balances[burner].sub(_value);
        totalSupply = totalSupply.sub(_value);
        Burn(burner, _value);
        Transfer(burner, address(0x0), _value);
        return true;
      }

    /**
     * Destroy tokens from other account
     *
     * Remove `_value` tokens from the system irreversibly on behalf of `_from`.
     *
     * @param _from the address of the sender
     * @param _value the amount of money to burn
     */
    function burnFrom(address _from, uint256 _value) 
        public
        onlyWhenBurnable(_value)
        onlyWhenNotFrozen(_from)
        onlyWhenNotFrozen(msg.sender)
        returns (bool success) {
        assert(transferFrom( _from, msg.sender, _value ));
        return burn(_value);
    }

    /**
     * Set allowance for other address and notify
     *
     * Allows `_spender` to spend no more than `_value` tokens on your behalf, and then ping the contract about it
     *
     * @param _spender The address authorized to spend
     * @param _value the max amount they can spend
     * @param _extraData some extra information to send to the approved contract
     */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData)
        public
        onlyWhenValidAddress(_spender)
        returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }

    /**
     * Freezes account and disables transfers/burning
     *  This is to manage regulatory hurdlers where contract owner is required to freeze some accounts.
     */
    function freezeAccount(address target, bool freeze) external onlyOwner {
        frozenAccount[target] = freeze;
        FrozenFunds(target, freeze);
    }

    /* Owner withdrawal of an ether deposited from Token ether balance */
    function withdrawToOwner(uint256 weiAmt) public onlyOwner {
        // do not allow zero transfer
        require(weiAmt > 0);
        owner.transfer(weiAmt);
        // signal the event for communication only it is meaningful
        Withdraw(this, msg.sender, weiAmt);
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

    function setTokenSaleContract(address _tokenSaleContract)
        external
        onlyWhenValidContractAddress(_tokenSaleContract)
        onlyOwner {
           require(_tokenSaleContract != tokenSaleContract);
           tokenSaleContract = _tokenSaleContract;
    }

    /// @dev Internal function to determine if an address is a contract
    /// @param _addr address The address being queried
    /// @return True if `_addr` is a contract
    function isContract(address _addr) constant internal returns(bool) {
        if (_addr == 0) {
            return false;
        }
        uint256 size;
        assembly {
            size: = extcodesize(_addr)
        }
        return (size > 0);
    }

    /**
     * @dev Function to send `_value` tokens to user (`_to`) from sale contract/owner
     * @param _to address The address that will receive the minted tokens.
     * @param _value uint256 The amount of tokens to be sent.
     * @return True if the operation was successful.
     */
    function sendToken(address _to, uint256 _value)
        public
        onlyWhenValidAddress(_to)
        onlyOwnerAndContract
        returns(bool) {
        address _from = owner;
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
        return true;
    }
    /**
     * @dev Batch transfer of tokens to addresses from owner's balance
     * @param addresses address[] The address that will receive the minted tokens.
     * @param _values uint256[] The amount of tokens to be sent.
     * @return True if the operation was successful.
     */
    function batchSendTokens(address[] addresses, uint256[] _values) 
        public onlyOwnerAndContract
        returns (bool) {
        require(addresses.length == _values.length);
        require(addresses.length <= 20); //only batches of 20 allowed
        uint i = 0;
        uint len = addresses.length;
        for (;i < len; i++) {
            sendToken(addresses[i], _values[i]);
        }
        return true;
    }
}