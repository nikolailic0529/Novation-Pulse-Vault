//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IVault {
    function reportLose(uint) external;
    function refill(uint) external;
    function payout(uint) external;
    function refillable() external view returns (uint);
}

contract MocStrategy is Ownable {
    using SafeERC20 for IERC20;

    IVault public vault;
    IERC20 public immutable asset;

    constructor(address _asset) {
        asset = IERC20(_asset);
    }

    function setVault(address _vault) external onlyOwner {
        vault = IVault(_vault);
    }

    function lose(uint _amount) external onlyOwner {
        asset.safeTransfer(msg.sender, _amount);
        vault.reportLose(_amount);
    }

    function payRewards(uint _amount) external onlyOwner {
        asset.safeTransferFrom(msg.sender, address(this), _amount);
        asset.safeApprove(address(vault), _amount);
        vault.payout(_amount);
    }

    function refillVault() external onlyOwner {
        uint refillAmount = vault.refillable();
        require (refillAmount > 0, "!refillable");
        asset.safeApprove(address(vault), refillAmount);
        vault.refill(refillAmount);
    }

    function close() external onlyOwner {
        uint refillAmount = asset.balanceOf(address(this));
        asset.safeApprove(address(vault), refillAmount);
        vault.refill(refillAmount);
    }

    function balance() external view returns (uint) {
        return asset.balanceOf(address(this));
    }
}