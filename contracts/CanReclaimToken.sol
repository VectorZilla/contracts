pragma solidity ^0.4.18;

import "./ownership/Ownable.sol";
import "./ERC20Basic.sol";
import "./SafeERC20.sol";

/**
 * @title Contracts that should be able to recover tokens
 * @author SylTi
 * @dev This allow a contract to recover any ERC20 token received in a contract by transferring the balance to the contract owner.
 * This will prevent any accidental loss of tokens.
 * https://github.com/OpenZeppelin/zeppelin-solidity/
 */
contract CanReclaimToken is Ownable {
  using SafeERC20 for ERC20Basic;

    //log event whenever withdrawal from this contract address happens
    event Withdraw(address indexed from, address indexed to, uint256 value);
  /**
   * @dev Reclaim all ERC20Basic compatible tokens
   * @param token ERC20Basic The address of the token contract
   */
  function reclaimToken(address token) external onlyOwner {
    if (token == 0x0) {
            owner.transfer(this.balance);
            return;
    }
    ERC20Basic ecr20BasicToken = ERC20Basic(token);
    uint256 balance = ecr20BasicToken.balanceOf(this);
    ecr20BasicToken.safeTransfer(owner, balance);
    Withdraw(msg.sender, owner, balance);
  }

}