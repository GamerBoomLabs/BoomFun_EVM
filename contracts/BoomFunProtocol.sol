// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BoomFunToken.sol";

// Uniswap V2 Router interface for adding liquidity between two ERC20 tokens
interface IUniswapV2Router02 {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );
}

contract BoomFunProtocol is Ownable, ReentrancyGuard {
    IERC20 public currencyToken;

    // Bonding Curve parameters
    uint256 public constant A = 1073000191;
    uint256 public constant B = 32190005730;
    uint256 public constant PROGRESS_THRESHOLD = 263300 * 10**18; // 100% PROGRESS

    // Platform fees
    uint256 public constant PLATFORM_FEE_BP = 50; // 0.5% (basis points)
    uint256 public constant DEX_FEE_BP = 50; // 0.5% (basis points)

    // Uniswap V2 Router address (Ethereum mainnet)
    address private constant UNISWAP_V2_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    IUniswapV2Router02 public uniswapRouter;

    uint256 public tokenCount = 1;
    uint256 public totalFeeCollected;
    mapping(uint256 => TokenInfo) public tokens;

    // Structs
    struct TokenInfo {
        address tokenAddress;
        string name;
        string symbol;
        address creator;
        uint256 tokenSold; //// Denominated in wei
        uint256 currencyCollected; // Denominated in wei
        bool isDEXPhase; // Added per-token DEX phase flag
    }

    // Events
    event TokenCreation(
        uint256 tokenId, address tokenAddress, string name, string symbol, uint256 launchTime, address tokenCreator
    );

    event TokenTrade(
        bool isTokenPurchase,
        uint256 tokenId,
        address indexed tokenAddress,
        address indexed trader,
        uint256 tokenAmount,
        uint256 currencyAmount
    );

    event DEXPoolCreation(address token, uint256 amountETH, uint256 amountToken);

    event Debug(string message, uint256 value);

    constructor(IERC20 _currencyToken) Ownable(msg.sender) {
        currencyToken = _currencyToken;
        uniswapRouter = IUniswapV2Router02(UNISWAP_V2_ROUTER);
    }

    // Create new fan token
    function createToken(string memory name, string memory symbol, bytes32 _salt)
        external
        nonReentrant
        returns (address, uint256)
    {
        require(bytes(name).length > 0 && bytes(symbol).length > 0, "Invalid name or symbol");

        // User transfers fan token creation fee to contract
        require(currencyToken.balanceOf(msg.sender) >= 50 * 10**18, "Insufficient currency token");
        currencyToken.transferFrom(msg.sender, address(this), 50 * 10**18);
        totalFeeCollected += 50 * 10**18;

        BoomFunToken token = new BoomFunToken{salt: _salt}(name, symbol, address(this));
        require(address(token) != address(0), "Token creation failed");
        require(tokens[tokenCount].tokenAddress == address(0), "Invalid tokenId");

        tokens[tokenCount] = TokenInfo({
            tokenAddress: address(token),
            name: name,
            symbol: symbol,
            creator: msg.sender,
            tokenSold: 0,
            currencyCollected: 0,
            isDEXPhase: false // Initialize DEX phase as false for the new token
        });

        emit TokenCreation(tokenCount, address(token), name, symbol, block.timestamp, msg.sender);

        uint256 currentTokenId = tokenCount;
        tokenCount++;

        return (address(token), currentTokenId);
    }

    // Purchase tokens: User buys fan tokens with specified amount of currency tokens
    function purchaseTokenWithCurrency(uint256 tokenId, uint256 currencyAmount) external nonReentrant {
        TokenInfo storage tokenInfo = tokens[tokenId];
        require(!tokenInfo.isDEXPhase, "DEX phase: Use DEX to trade");
        // Check if market cap threshold is reached
        checkProgress(tokenId);

        require(tokenInfo.tokenAddress != address(0), "Invalid token");
        require(
            currencyAmount > 0 && currencyToken.balanceOf(msg.sender) >= currencyAmount, "Insufficient currency token"
        );

        // User transfers currency token to contract
        currencyToken.transferFrom(msg.sender, address(this), currencyAmount);

        // Calculate platform fee
        uint256 fee = (currencyAmount * PLATFORM_FEE_BP) / 10000;
        totalFeeCollected += fee;
        uint256 netFunds = currencyAmount - fee;

        // Calculate amount of currency already collected
        uint256 x1 = tokenInfo.currencyCollected;
        uint256 denominator = 30 * 10**18  + (x1 + netFunds) / 3000;

        // Calculate the supply after trade based on Bonding Curve formula
        uint256 y2 = A * 10**18 - (B * 10**36 / denominator);
        uint256 tokenAmount = y2 - tokenInfo.tokenSold;

        // Avoiding too deep stack error
        {
            // Check if the contract has enough tokens to transfer
            IERC20 boomFunToken = IERC20(tokenInfo.tokenAddress);
            uint256 contractTokenBalance = boomFunToken.balanceOf(address(this));
            require(contractTokenBalance >= tokenAmount, "ERC20InsufficientBalance");

            // Transfer tokens to user
            boomFunToken.transfer(msg.sender, tokenAmount);
        }

        // Update token info
        tokenInfo.currencyCollected += netFunds;
        tokenInfo.tokenSold += tokenAmount;

        // Check if progress threshold is reached
        checkProgress(tokenId);

        emit TokenTrade(true, tokenId, tokenInfo.tokenAddress, msg.sender, tokenAmount, currencyAmount);
    }

    // Purchase tokens: User specifies purchase amount of fan token
    function purchaseToken(uint256 tokenId, uint256 tokenAmount) external nonReentrant {
        TokenInfo storage tokenInfo = tokens[tokenId];
        require(!tokenInfo.isDEXPhase, "DEX phase: Use DEX to trade");
        // Check if progress threshold is reached
        checkProgress(tokenId);

        require(tokenAmount > 0, "Amount must be greater than zero");
        require(tokenInfo.tokenAddress != address(0), "Invalid token");

        // Current token info
        uint256 x1 = tokenInfo.currencyCollected;
        uint256 y1 = tokenInfo.tokenSold;

        // Calculate token info after trade
        uint256 y2 = y1 + tokenAmount;

        uint256 x2 = (B * 10**36 / (A * 10**18 - y2) - 30 * 10**18) * 3000;

        // Calculate required funds
        uint256 netFunds = x2 - x1; // Currency token required in wei

        // Calculate fee
        uint256 fee = (netFunds * PLATFORM_FEE_BP) / 10000;
        uint256 requiredFunds = netFunds + fee;

        // User transfers currency token to contract
        require(requiredFunds > 0 && currencyToken.balanceOf(msg.sender) >= requiredFunds, "Insufficient currency token");
        currencyToken.transferFrom(msg.sender, address(this), requiredFunds);

        totalFeeCollected += fee;
        tokenInfo.currencyCollected += netFunds;

        // Transfer tokens to user
        tokenInfo.tokenSold = y2;

        // Check if the contract has enough tokens to transfer
        IERC20 boomFunToken = IERC20(tokenInfo.tokenAddress);
        uint256 contractTokenBalance = boomFunToken.balanceOf(address(this));
        require(contractTokenBalance >= tokenAmount, "ERC20InsufficientBalance");

        BoomFunToken(tokenInfo.tokenAddress).transfer(msg.sender, tokenAmount);

        // Check if market cap threshold is reached
        checkProgress(tokenId);

        emit TokenTrade(true, tokenId, tokenInfo.tokenAddress, msg.sender, tokenAmount, requiredFunds);
    }

    // Sell tokens: User sells fan tokens back to the contract for currency token
    function sellToken(uint256 tokenId, uint256 tokenAmount) external nonReentrant {
        TokenInfo storage tokenInfo = tokens[tokenId];
        require(!tokenInfo.isDEXPhase, "DEX phase: Use DEX to trade");
        // Check if progress threshold is reached
        checkProgress(tokenId);

        require(tokenInfo.tokenAddress != address(0), "Invalid token");
        require(tokenAmount > 0 && IERC20(tokenInfo.tokenAddress).balanceOf(msg.sender) >= tokenAmount, "Insufficient fan token");

        // Calculate
        uint256 x1 = tokenInfo.currencyCollected;
        uint256 y1 = tokenInfo.tokenSold;
        uint256 y2 = y1 - tokenAmount;
        uint256 x2 = (B * 10**36 / (A * 10**18 - y2) - 30 * 10**18) * 3000;

        // Calculate currency amount to pay
        uint256 currencyToPay = x1 - x2;
        require(currencyToken.balanceOf(address(this)) >= currencyToPay, "Insufficient currency token in contract");

        // Calculate fee
        uint256 fee = (currencyToPay * PLATFORM_FEE_BP) / 10000;
        totalFeeCollected += fee;
        uint256 netCurrencyToPay = currencyToPay - fee;

        // Update token info before external calls
        tokenInfo.currencyCollected = x2;
        tokenInfo.tokenSold = y2;

        // Transfer tokens from user to contract and burn them
        BoomFunToken(tokenInfo.tokenAddress).transferFrom(msg.sender, address(this), tokenAmount);
        BoomFunToken(tokenInfo.tokenAddress).burn(tokenAmount);

        // Transfer currency token to user
        currencyToken.transfer(msg.sender, netCurrencyToPay);

        emit TokenTrade(false, tokenId, tokenInfo.tokenAddress, msg.sender, tokenAmount, currencyToPay);
    }

    // Check if market cap threshold is reached, if so, transition to DEX phase
    function checkProgress(uint256 tokenId) internal {
        TokenInfo storage tokenInfo = tokens[tokenId];

        if (!tokenInfo.isDEXPhase && tokenInfo.currencyCollected >= PROGRESS_THRESHOLD) {
            tokenInfo.isDEXPhase = true;
            // Transfer remaining fan tokens and collected currency tokens to DEX to form permanent LP
            transferToDEX(tokenId);
        }
    }

    // Add logging to transferToDEX function
    function transferToDEX(uint256 tokenId) internal {
        TokenInfo storage tokenInfo = tokens[tokenId];
        uint256 tokenAmount = BoomFunToken(tokenInfo.tokenAddress).balanceOf(address(this));
        uint256 currencyAmount = tokenInfo.currencyCollected - 20000 * 10**18;

        emit Debug("Token Amount", tokenAmount);
        emit Debug("Currency Amount", currencyAmount);

        if (tokenAmount > 0 && currencyAmount > 0) {
            // Approve Uniswap Router to spend tokens
            BoomFunToken(tokenInfo.tokenAddress).approve(address(uniswapRouter), tokenAmount);
            currencyToken.approve(address(uniswapRouter), currencyAmount);

            // Add liquidity
            uniswapRouter.addLiquidity(
                tokenInfo.tokenAddress,
                address(currencyToken),
                tokenAmount,
                currencyAmount,
                0, // Accept any amount of fan tokens
                0, // Accept any amount of currency token
                address(this), // Liquidity tokens held by the contract itself
                block.timestamp
            );

            emit DEXPoolCreation(tokenInfo.tokenAddress, tokenAmount, currencyAmount);
        } else {
            emit Debug("Insufficient token or currency amount", 0);
        }
    }

    // Withdraw platform fees to platform address
    function withdrawFees(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(amount <= totalFeeCollected, "Insufficient balance");
        currencyToken.transfer(to, amount);
    }

    // Allow contract to receive ETH
    receive() external payable {}

    // Adding read-only function to get Bonding Curve information
    function getBondingCurveInfo(uint256 tokenId) external view returns (
        uint256 price,
        uint256 bondingCurveProgress, // percentage
        uint256 marketValue
    ) {
        TokenInfo storage tokenInfo = tokens[tokenId];
        require(tokenInfo.tokenAddress != address(0), "Invalid token");

        // Calculate current price
        // Price calculation based on current currency collected and supply
        uint256 x = tokenInfo.currencyCollected;
        uint256 denominator = 30 * 10**18 + (x) / 3000;
        // Price can be defined as the price under tiny changes, approximately equal to dy/dx
        // Simplified here as current price = B * 10**36 / denominator^2
        uint256 currentPrice = (B * 10**36) / (denominator * denominator);

        // Bonding Curve progress percentage
        uint256 progress = (tokenInfo.currencyCollected * 100 * 1e18) / PROGRESS_THRESHOLD;
        // To return percentage, keeping 18 decimal places

        // Market value defined as the amount of currency collected
        uint256 value = tokenInfo.currencyCollected;

        return (currentPrice, progress / 1e18, value);
    }
}
