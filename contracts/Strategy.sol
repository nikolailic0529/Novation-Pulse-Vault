// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITefiVault.sol";

contract Strategy is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct CexInfo {
        address addr;
        string name;
        uint weight;
        uint underlying;
        uint profit;
    }

    ITefiVaultForPulse public vault;
    IERC20 public asset;
    address public operator = 0xe4c51294d509023973F3B3d802d8BeA1422dA3E3;

    mapping (address => uint) public cexWeights;
    CexInfo[] public cexs;

    address public traderWallet = 0x273B4Dc588695Ab7B88Bd47c5e40E4ba227bb6e5;
    address public platformWallet = 0x28A0a8d8851e4C0388d7def56e2196dDc078F859;
    address public treasuryWallet = 0x5aBB3Dd5015c12d96492Df453F9dC19b777CCFEB;
    address public insuranceWallet = 0xF4f270a88141523F8f8332e64ECb435807266098;
    address public devWallet = 0x6e48745Fb2DfE5495F66B2B789f08E1911216f8A;

    uint public totalFee = 150;     // 15% totally
    uint public traderFee = 50;     // 5%
    uint public platformFee = 45;   // 4.5%
    uint public treasuryFee = 20;   // 2%
    uint public insuranceFee = 20;  // 2%
    uint public devFee = 15;        // 1.5%

    event Lost(uint indexed cexId, uint amount);
    event Earned(uint indexed cexId, uint amount);
    event Refilled(uint indexed cexId, uint amount);
    event Deposited(uint amount);
    event Closed(uint amount);

    modifier onlyVault {
        require (msg.sender == address(vault), "!vault");
        _;
    }

    modifier onlyOperator {
        require (msg.sender == operator, "!operator");
        _;
    }

    constructor(address _asset) {
        asset = IERC20(_asset);
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    function setVault(address _vault) external onlyOwner {
        vault = ITefiVaultForPulse(_vault);
        if (address(vault) != address(0)) {
            asset.safeApprove(address(vault), 0);
        }
        asset.safeApprove(_vault, type(uint).max);
    }

    function setFee(
        uint _total,
        uint _trader,
        uint _platform,
        uint _treasury,
        uint _insurance,
        uint _dev
    ) external onlyOwner {
        require (_trader + _platform + _treasury + _insurance + _dev == _total, "!fees");
        
        totalFee = _total;
        traderFee = _trader;
        platformFee = _platform;
        treasuryFee = _treasury;
        insuranceFee = _insurance;
        devFee = _dev;
    }

    function setTraderWallet(address _wallet) external onlyOwner {
        traderWallet = _wallet;
    }

    function setPlatformWallet(address _wallet) external onlyOwner {
        platformWallet = _wallet;
    }

    function setTreasuryWallet(address _wallet) external onlyOwner {
        treasuryWallet = _wallet;
    }

    function setInsuranceWallet(address _wallet) external onlyOwner {
        insuranceWallet = _wallet;
    }

    function setDevWallet(address _wallet) external onlyOwner {
        devWallet = _wallet;
    }

    function addCex(address _addr, string memory _name) external onlyOperator {
        cexs.push(CexInfo({
            addr: _addr,
            name: _name,
            weight: 0,
            underlying: 0,
            profit: 0
        }));
    }

    function getCexList() external view returns (CexInfo[] memory) {
        return cexs;
    }

    function cexCount() external view returns (uint) {
        return cexs.length;
    }

    function updateCex(uint _index, address _addr, string calldata _name) external onlyOperator {
        require (_index < cexs.length, "!index");

        cexs[_index].addr = _addr;
        cexs[_index].name = _name;
    }

    function updateCexWeights(uint[] calldata _weights) external onlyOperator nonReentrant {
        require (_weights.length == cexs.length, "!weights length");

        uint totalWeight;
        for (uint i = 0; i < _weights.length; i++) {
            totalWeight += _weights[i];
        }

        require (totalWeight == 100, "!weights");

        for (uint i = 0; i < _weights.length; i++) {
            cexs[i].weight = _weights[i];
        }
    }

    function refillable() public view returns (uint) {
        return vault.refillable();
    }

    function underlying() public view returns (uint) {
        return vault.underlying();
    }

    function deposit(uint _amount) external onlyVault nonReentrant whenNotPaused {
        uint bal = asset.balanceOf(address(this));
        require (bal >= _amount, "!amount");

        _deposit();

        emit Deposited(bal - _amount);
    }

    function _deposit() internal {
        uint bal = asset.balanceOf(address(this));
        if (bal == 0) return;

        for (uint i = 0; i < cexs.length; i++) {
            CexInfo storage cex = cexs[i];
            uint weight = cex.weight;
            if (weight == 0) continue;

            uint amount = bal * weight / 100;
            asset.safeTransfer(cex.addr, amount);
            cex.underlying += amount;
        }
    }

    function reportProfit(uint _amount, uint _cexId) external onlyOperator nonReentrant {
        require (_cexId < cexs.length, "!index");
        require (_amount > 0, "!profit");
        uint _operatorBal = asset.balanceOf(operator);
        require (_operatorBal >= _amount, "!profit fund");

        asset.safeTransferFrom(operator, address(this), _amount);

        // If someone sent the fund directly here, it will be added to the profit
        _amount = asset.balanceOf(address(this));

        cexs[_cexId].profit += _amount;

        uint feeAmount = _amount * totalFee / 1000;
        if (feeAmount > 0) shareFee(feeAmount);

        vault.reportProfit(_amount - feeAmount);

        emit Earned(_cexId, _amount);
    }

    function reportLoss(uint _amount, uint _cexId) external onlyOperator nonReentrant {
        require (_cexId < cexs.length, "!index");
        require (cexs[_cexId].underlying >= _amount, "!loss amount");
        
        vault.reportLoss(_amount);
        cexs[_cexId].underlying -= _amount;

        emit Lost(_cexId, _amount);
    }

    function shareFee(uint _amount) internal {
        _transferFee(traderWallet, _amount, traderFee);
        _transferFee(platformWallet, _amount, platformFee);
        _transferFee(treasuryWallet, _amount, treasuryFee);
        _transferFee(insuranceWallet, _amount, insuranceFee);
        _transferFee(devWallet, _amount, devFee);
    }

    function _transferFee(address _wallet, uint _total, uint _fee) internal {
        uint amount = _total * _fee / totalFee;
        asset.safeTransfer(_wallet, amount);
    }

    function refill(uint _amount, uint _cexId) public onlyOperator nonReentrant {
        require (_cexId < cexs.length, "!index");
        require (cexs[_cexId].underlying >= _amount, "!cex amount");
        uint _operatorBal = asset.balanceOf(operator);
        require (_operatorBal >= _amount, "!refillable fund");

        asset.safeTransferFrom(operator, address(this), _amount);
        vault.refill(_amount);
        cexs[_cexId].underlying -= _amount;

        emit Refilled(_cexId, _amount);
    }

    function close() external onlyOperator whenPaused nonReentrant {
        uint _underlying = underlying();
        uint _operatorBal = asset.balanceOf(operator);
        uint _currentBal = asset.balanceOf(address(this));
        require (_operatorBal >= _underlying, "!underlying");

        if (_currentBal > 0) {
            vault.reportProfit(_currentBal);
        }

        if (_underlying > 0) {
            asset.safeTransferFrom(operator, address(this), _underlying);
        }
        
        vault.close();

        for (uint i = 0; i < cexs.length; i++) {
            cexs[i].underlying = 0;
            // cexs[i].profit = 0;
        }

        emit  Closed(_underlying);
    }

    function refillAll(uint _cexId) external onlyOperator {
        uint _refillable = vault.refillable();
        refill(_refillable, _cexId);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}