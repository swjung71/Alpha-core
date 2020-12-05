pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract ASTFarm is ERC20("ASTFarm", "xAST"){
    using SafeMath for uint256;
    IERC20 public AST;

    constructor(IERC20 _AST) public {
        AST = _AST;
    }

    // Enter the bar. Pay some AST. Earn some shares.
    function enter(uint256 _amount) public {
        uint256 totalAST = AST.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        if (totalShares == 0 || totalAST == 0) {
            _mint(msg.sender, _amount);
        } else {
            uint256 what = _amount.mul(totalShares).div(totalAST);
            _mint(msg.sender, what);
        }
        AST.transferFrom(msg.sender, address(this), _amount);
    }

    // Leave the bar. Claim back your ASTs.
    function leave(uint256 _share) public {
        uint256 totalShares = totalSupply();
        uint256 what = _share.mul(AST.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        AST.transfer(msg.sender, what);
    }
}