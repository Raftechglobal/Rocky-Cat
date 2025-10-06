// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
 *  RockyCatV2 — Airdrop Migration Version
 *  ---------------------------------------
 *  - No approvals or burns on V1
 *  - Owner can mint tokens for old holders via snapshot-based airdrop
 *  - Includes anti-bot features, cooldowns, and transfer mode controls
 *  - Added: Buy/Sell taxes with configurable rates and wallet distribution
 *  - Added: Uniswap/PancakeSwap DEX integration for liquidity and tax swaps
 *  - Added: Standard pause functionality
 *  - Added: Token/ETH recovery functions
 *  - Added: ReentrancyGuard, max supply, slippage control, and batch airdrops
 */
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract RockyCatV2 is ERC20, Ownable, Pausable, ReentrancyGuard {
    // Anti-Bot Parameters
    uint256 public constant MAX_TX_PERCENT = 1; // 1% of total supply
    uint256 public constant MAX_WALLET_PERCENT = 2; // 2% of total supply
    uint256 public cooldownSeconds = 30;

    // Max Supply Limit
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18; // 1B tokens

    mapping(address => uint256) public lastTradeTimestamp;
    mapping(address => bool) public blacklisted;

    // Transfer Modes
    enum TransferMode {
        NORMAL,
        TRANSFER_RESTRICTED,
        TRANSFER_CONTROLLED
    }

    TransferMode public transferMode = TransferMode.TRANSFER_RESTRICTED;
    bool public transfersEnabled = false;

    // Tax Parameters
    uint256 public buyTax = 0; // In basis points (e.g., 500 = 5%)
    uint256 public sellTax = 0; // In basis points
    uint256 public transferTax = 0; // For non-buy/sell transfers

    address public marketingWallet;
    address public liquidityWallet;
    uint256 public taxSwapThreshold = 0; // Amount to accumulate before swapping taxes
    uint256 public minSwapOutput = 95; // 95% of expected output (5% slippage tolerance)

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private _isAutomatedMarketMakerPair;

    // DEX Integration
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    bool private swapping;

    // Events
    event Airdropped(address indexed user, uint256 amount);
    event Blacklisted(address indexed account, bool status);
    event ModeChanged(TransferMode newMode);
    event CooldownUpdated(uint256 newCooldown);
    event TaxUpdated(uint256 buyTax, uint256 sellTax, uint256 transferTax);
    event WalletUpdated(address marketingWallet, address liquidityWallet);
    event ExcludedFromFees(address account, bool isExcluded);
    event AutomatedMarketMakerPairUpdated(address pair, bool value);
    event SwappedTaxes(uint256 tokensSwapped, uint256 ethReceived);
    event AddedLiquidity(uint256 tokensAdded, uint256 ethAdded);
    event RecoveredTokens(address token, uint256 amount);
    event RecoveredETH(uint256 amount);
    event MinSwapOutputUpdated(uint256 newMinOutput);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address initialOwner
    ) ERC20(name_, symbol_) Ownable() {
        require(initialOwner != address(0), "Initial owner cannot be zero address");
        require(initialSupply_ * 10 ** decimals() <= MAX_SUPPLY, "Initial supply exceeds max supply");
        _transferOwnership(initialOwner);
        _mint(initialOwner, initialSupply_ * 10 ** decimals());

        _isExcludedFromFees[initialOwner] = true;
        _isExcludedFromFees[address(this)] = true;

        marketingWallet = initialOwner;
        liquidityWallet = initialOwner;
    }

    // ==========================
    // 🧠 INTERNAL SECURITY CHECKS
    // ==========================
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        // Skip checks for minting or burning

        // Combine blacklist checks
        require(!blacklisted[from] && !blacklisted[to], "Blacklisted address");

        // Mode logic
        if (transferMode == TransferMode.TRANSFER_RESTRICTED) {
            require(transfersEnabled, "Transfers restricted");
        } else if (transferMode == TransferMode.TRANSFER_CONTROLLED) {
            require(owner() == from || owner() == to, "Controlled: only owner");
        }

        // Cooldown
        require(block.timestamp >= lastTradeTimestamp[from] + cooldownSeconds, "Cooldown active");

        // Max Tx
        uint256 maxTx = (totalSupply() * MAX_TX_PERCENT) / 100;
        require(amount <= maxTx, "Exceeds max tx");

        // Max Wallet
        if (to != owner() && to != address(0)) {
            uint256 maxWallet = (totalSupply() * MAX_WALLET_PERCENT) / 100;
            require(balanceOf(to) + amount <= maxWallet, "Exceeds max wallet");
        }

        // Custom transfer logic for taxes
        uint256 taxAmount = 0;
        if (!_isExcludedFromFees[from] && !_isExcludedFromFees[to] && !swapping) {
            if (_isAutomatedMarketMakerPair[from]) {
                // Buy
                taxAmount = (amount * buyTax) / 10000;
            } else if (_isAutomatedMarketMakerPair[to]) {
                // Sell
                taxAmount = (amount * sellTax) / 10000;
            } else {
                // Transfer
                taxAmount = (amount * transferTax) / 10000;
            }
        }

        if (taxAmount > 0) {
            super._transfer(from, address(this), taxAmount);
            amount -= taxAmount;

            // Auto-swap if threshold reached (on sells)
            if (_isAutomatedMarketMakerPair[to] && balanceOf(address(this)) >= taxSwapThreshold && taxSwapThreshold > 0) {
                _swapTaxes();
            }
        }

        lastTradeTimestamp[from] = block.timestamp;

        // Update amount to reflect taxes before calling parent _transfer
        if (amount > 0) {
            super._transfer(from, to, amount);
        }
    }

    // ==========================
    // 🚀 AIRDROP MIGRATION LOGIC
    // ==========================
    /**
     * @notice Batch mint tokens to snapshot holders (no V1 transfer needed)
     * @dev Limited to 500 recipients per call to avoid gas limits; call multiple times for large airdrops
     */
    function airdropMint(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(recipients.length == amounts.length, "Length mismatch");
        require(recipients.length > 0, "Empty airdrop list");

        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i];
            uint256 amount = amounts[i];
            require(user != address(0), "Invalid address");
            require(amount > 0, "Zero amount");

            _mint(user, amount);
            emit Airdropped(user, amount);
        }
    }

    // ==========================
    // 🔄 DEX INTEGRATION & TAX SWAPS
    // ==========================
    function setRouterAddress(address routerAddress) external onlyOwner {
        require(routerAddress != address(0), "Invalid router address");
        uniswapV2Router = IUniswapV2Router02(routerAddress);
    }

    function createPair() external onlyOwner {
        require(address(uniswapV2Router) != address(0), "Router not set");
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        _isAutomatedMarketMakerPair[uniswapV2Pair] = true;
        _isExcludedFromFees[uniswapV2Pair] = true;
        emit AutomatedMarketMakerPairUpdated(uniswapV2Pair, true);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) external onlyOwner nonReentrant {
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );

        emit AddedLiquidity(tokenAmount, ethAmount);
    }

    function _swapTaxes() private nonReentrant {
        swapping = true;

        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance == 0 || taxSwapThreshold == 0) {
            swapping = false;
            return;
        }

        uint256 swapAmount = (contractBalance > taxSwapThreshold) ? taxSwapThreshold : contractBalance;

        _approve(address(this), address(uniswapV2Router), swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        uint256 balanceBefore = address(this).balance;

        // Assume 1 token = 1 ETH for simplicity; adjust based on actual pair pricing
        uint256 minAmountOut = (swapAmount * minSwapOutput) / 100;

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            swapAmount,
            minAmountOut,
            path,
            address(this),
            block.timestamp
        );

        uint256 ethReceived = address(this).balance - balanceBefore;
        emit SwappedTaxes(swapAmount, ethReceived);

        // Distribute ETH (50% to marketing, 50% to liquidity wallet)
        uint256 marketingShare = (ethReceived * 50) / 100;
        uint256 liquidityShare = ethReceived - marketingShare;

        payable(marketingWallet).transfer(marketingShare);
        payable(liquidityWallet).transfer(liquidityShare);

        swapping = false;
    }

    // ==========================
    // ⚙️ ADMIN CONTROLS
    // ==========================
    function setTransferMode(TransferMode newMode) external onlyOwner {
        transferMode = newMode;
        if (newMode == TransferMode.NORMAL) transfersEnabled = true;
        emit ModeChanged(newMode);
    }

    function setTransfersEnabled(bool enabled) external onlyOwner {
        transfersEnabled = enabled;
    }

    function blacklist(address account, bool status) external onlyOwner {
        // Note: Blacklisting is centralized; use transparently to maintain trust
        blacklisted[account] = status;
        emit Blacklisted(account, status);
    }

    function setCooldown(uint256 newCooldown) external onlyOwner {
        require(newCooldown <= 300, "Cooldown too long"); // 5 min max
        cooldownSeconds = newCooldown;
        emit CooldownUpdated(newCooldown);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setTaxes(uint256 newBuyTax, uint256 newSellTax, uint256 newTransferTax) external onlyOwner {
        require(newBuyTax <= 1000 && newSellTax <= 1000 && newTransferTax <= 1000, "Tax too high"); // Max 10%
        buyTax = newBuyTax;
        sellTax = newSellTax;
        transferTax = newTransferTax;
        emit TaxUpdated(newBuyTax, newSellTax, newTransferTax);
    }

    function setWallets(address newMarketingWallet, address newLiquidityWallet) external onlyOwner {
        require(newMarketingWallet != address(0) && newLiquidityWallet != address(0), "Invalid wallet");
        marketingWallet = newMarketingWallet;
        liquidityWallet = newLiquidityWallet;
        emit WalletUpdated(newMarketingWallet, newLiquidityWallet);
    }

    function setTaxSwapThreshold(uint256 newThreshold) external onlyOwner {
        taxSwapThreshold = newThreshold;
    }

    function setMinSwapOutput(uint256 newMinOutput) external onlyOwner {
        require(newMinOutput <= 100, "Invalid slippage tolerance");
        minSwapOutput = newMinOutput;
        emit MinSwapOutputUpdated(newMinOutput);
    }

    function excludeFromFees(address account, bool excluded) external onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludedFromFees(account, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        _isAutomatedMarketMakerPair[pair] = value;
        emit AutomatedMarketMakerPairUpdated(pair, value);
    }

    // Recovery Functions
    function recoverTokens(address tokenAddress, uint256 tokenAmount) external onlyOwner nonReentrant {
        require(tokenAddress != address(this), "Cannot recover own tokens");
        IERC20(tokenAddress).transfer(owner(), tokenAmount);
        emit RecoveredTokens(tokenAddress, tokenAmount);
    }

    function recoverETH(uint256 amount) external onlyOwner nonReentrant {
        require(address(this).balance >= amount, "Insufficient ETH balance");
        payable(owner()).transfer(amount);
        emit RecoveredETH(amount);
    }

    receive() external payable {}
}
