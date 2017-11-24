pragma solidity ^0.4.13;

import './math/SafeMath.sol';
import "./VZToken.sol";
import "./ownership/Ownable.sol";
import "./Pausable.sol";
import "./HasNoTokens.sol";

contract VZTCrowdsale is Ownable, Pausable, HasNoTokens {
    using SafeMath for uint256;

    string public constant NAME = "VectorZilla Crowdsale";
    string public constant VERSION = "0.1";

    VZToken token;

    //TBD

}