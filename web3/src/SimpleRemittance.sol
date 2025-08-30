// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Interface to interact with your RMR token
interface IRemittanceRewards {
    function mint(address to, uint256 amount) external;
}

/**
 * @title SimpleRemittance
 * @dev A clean remittance contract for voice-enabled transfers with RMR rewards
 * @notice Frontend handles username to address conversion
 */
contract SimpleRemittance is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // State variables
    mapping(address => bool) public supportedStablecoins;
    mapping(bytes32 => bool) public completedTransactions;
    mapping(address => uint256) public totalSentByUser; // Track user volumes
    
    // Fee structure
    uint256 public feePercentage = 50; // 0.5% (50 basis points)
    uint256 public constant MAX_FEE = 300; // 3% maximum fee
    address public feeRecipient;
    
    // Rewards system
    IRemittanceRewards public rmrToken;
    uint256 public rewardRate = 1; // 1 RMR per $100 USD sent
    uint256 public constant REWARD_DENOMINATOR = 100; // $100 = 100 * 10^6 USDC units
    
    // Milestone rewards
    mapping(address => bool) public firstTransferBonus;
    mapping(address => bool) public milestone1000; // $1000 milestone
    mapping(address => bool) public milestone5000; // $5000 milestone
    
    // Transaction tracking
    uint256 public transactionCounter;
    
    // Events
    event RemittanceSent(
        address indexed sender,
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint256 fee,
        bytes32 transactionId,
        uint256 timestamp
    );
    
    event RewardsEarned(
        address indexed user,
        uint256 volumeRewards,
        uint256 milestoneRewards,
        uint256 totalRewards
    );
    
    event StablecoinAdded(address indexed token, string symbol);
    event StablecoinRemoved(address indexed token);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event RMRTokenUpdated(address oldToken, address newToken);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    
    // Custom errors
    error UnsupportedStablecoin();
    error InvalidAmount();
    error InvalidRecipient();
    error TransactionAlreadyCompleted();
    error InvalidFeePercentage();
    error InsufficientBalance();
    error InvalidRMRToken();

    /**
     * @dev Constructor
     * @param _feeRecipient Address to receive transaction fees
     * @param _rmrToken Address of the RMR rewards token
     */
    constructor(address _feeRecipient, address _rmrToken) Ownable(msg.sender) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(_rmrToken != address(0), "Invalid RMR token");
        feeRecipient = _feeRecipient;
        rmrToken = IRemittanceRewards(_rmrToken);
    }

    /**
     * @dev Send remittance to a wallet address with automatic RMR rewards
     * @param _recipient The wallet address to send to
     * @param _stablecoin Address of the stablecoin to send  
     * @param _amount Amount to send (in token's smallest unit)
     * @param _transactionId Unique transaction ID for voice confirmation
     */
    function sendRemittance(
        address _recipient,
        address _stablecoin,
        uint256 _amount,
        bytes32 _transactionId
    ) external nonReentrant whenNotPaused {
        // Validation checks
        if (!supportedStablecoins[_stablecoin]) revert UnsupportedStablecoin();
        if (_amount == 0) revert InvalidAmount();
        if (_recipient == address(0)) revert InvalidRecipient();
        if (_recipient == msg.sender) revert InvalidRecipient();
        if (completedTransactions[_transactionId]) revert TransactionAlreadyCompleted();

        // Check sender has enough balance
        IERC20 token = IERC20(_stablecoin);
        if (token.balanceOf(msg.sender) < _amount) revert InsufficientBalance();

        // Calculate fee
        uint256 fee = (_amount * feePercentage) / 10000;
        uint256 amountAfterFee = _amount - fee;

        // Transfer tokens from sender to contract first
        token.safeTransferFrom(msg.sender, address(this), _amount);

        // Transfer fee to fee recipient
        if (fee > 0) {
            token.safeTransfer(feeRecipient, fee);
        }

        // Transfer remaining amount to recipient
        token.safeTransfer(_recipient, amountAfterFee);

        // Mark transaction as completed
        completedTransactions[_transactionId] = true;
        transactionCounter++;

        // Update user's total sent amount
        totalSentByUser[msg.sender] += _amount;

        // Calculate and mint RMR rewards
        _distributeRewards(msg.sender, _amount);

        // Emit event for frontend tracking
        emit RemittanceSent(
            msg.sender,
            _recipient,
            _stablecoin,
            amountAfterFee,
            fee,
            _transactionId,
            block.timestamp
        );
    }

    /**
     * @dev Internal function to calculate and distribute RMR rewards
     * @param _user User who sent the remittance
     * @param _amount Amount sent (before fees)
     */
    function _distributeRewards(address _user, uint256 _amount) internal {
        uint256 volumeRewards = 0;
        uint256 milestoneRewards = 0;

        // Volume-based rewards: 1 RMR per $100 sent
        // Assuming 6 decimals for stablecoin (USDC format)
        volumeRewards = (_amount * rewardRate) / (REWARD_DENOMINATOR * 10**6);

        // First transfer bonus
        if (!firstTransferBonus[_user]) {
            milestoneRewards += 50 * 10**18; // 50 RMR tokens
            firstTransferBonus[_user] = true;
        }

        // Milestone bonuses
        uint256 totalSent = totalSentByUser[_user];
        
        // $1000 milestone (1000 * 10^6 USDC units)
        if (totalSent >= 1000 * 10**6 && !milestone1000[_user]) {
            milestoneRewards += 100 * 10**18; // 100 RMR tokens
            milestone1000[_user] = true;
        }
        
        // $5000 milestone (5000 * 10^6 USDC units)
        if (totalSent >= 5000 * 10**6 && !milestone5000[_user]) {
            milestoneRewards += 500 * 10**18; // 500 RMR tokens
            milestone5000[_user] = true;
        }

        // Mint total rewards
        uint256 totalRewards = volumeRewards + milestoneRewards;
        if (totalRewards > 0) {
            rmrToken.mint(_user, totalRewards);
            
            emit RewardsEarned(_user, volumeRewards, milestoneRewards, totalRewards);
        }
    }

    /**
     * @dev Estimate transaction cost including fees and potential rewards
     * @param _amount The amount to send
     * @param _user User address to check for milestone eligibility
     * @return amountAfterFee Amount recipient will receive
     * @return fee The fee amount
     * @return estimatedRewards Estimated RMR rewards user will earn
     */
    function estimateTransactionCost(uint256 _amount, address _user) 
        external 
        view 
        returns (uint256 amountAfterFee, uint256 fee, uint256 estimatedRewards) 
    {
        fee = (_amount * feePercentage) / 10000;
        amountAfterFee = _amount - fee;
        
        // Calculate estimated rewards
        uint256 volumeRewards = (_amount * rewardRate) / (REWARD_DENOMINATOR * 10**6);
        uint256 milestoneRewards = 0;
        
        // Check potential milestone bonuses
        if (!firstTransferBonus[_user]) {
            milestoneRewards += 50 * 10**18;
        }
        
        uint256 newTotal = totalSentByUser[_user] + _amount;
        if (newTotal >= 1000 * 10**6 && !milestone1000[_user]) {
            milestoneRewards += 100 * 10**18;
        }
        if (newTotal >= 5000 * 10**6 && !milestone5000[_user]) {
            milestoneRewards += 500 * 10**18;
        }
        
        estimatedRewards = volumeRewards + milestoneRewards;
        
        return (amountAfterFee, fee, estimatedRewards);
    }

    // ============ REWARDS ADMIN FUNCTIONS ============

    /**
     * @dev Update RMR token address
     * @param _newRMRToken New RMR token address
     */
    function updateRMRToken(address _newRMRToken) external onlyOwner {
        require(_newRMRToken != address(0), "Invalid RMR token");
        address oldToken = address(rmrToken);
        rmrToken = IRemittanceRewards(_newRMRToken);
        emit RMRTokenUpdated(oldToken, _newRMRToken);
    }

    /**
     * @dev Update reward rate
     * @param _newRate New reward rate (RMR per $100)
     */
    function updateRewardRate(uint256 _newRate) external onlyOwner {
        uint256 oldRate = rewardRate;
        rewardRate = _newRate;
        emit RewardRateUpdated(oldRate, _newRate);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @dev Add a supported stablecoin
     * @param _token Address of the stablecoin contract
     * @param _symbol Symbol of the token for events
     */
    function addStablecoin(address _token, string calldata _symbol) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        supportedStablecoins[_token] = true;
        emit StablecoinAdded(_token, _symbol);
    }

    /**
     * @dev Remove a supported stablecoin
     * @param _token Address of the stablecoin contract
     */
    function removeStablecoin(address _token) external onlyOwner {
        supportedStablecoins[_token] = false;
        emit StablecoinRemoved(_token);
    }

    /**
     * @dev Update fee percentage
     * @param _newFeePercentage New fee in basis points (100 = 1%)
     */
    function updateFeePercentage(uint256 _newFeePercentage) external onlyOwner {
        if (_newFeePercentage > MAX_FEE) revert InvalidFeePercentage();
        
        uint256 oldFee = feePercentage;
        feePercentage = _newFeePercentage;
        
        emit FeeUpdated(oldFee, _newFeePercentage);
    }

    /**
     * @dev Update fee recipient
     * @param _newFeeRecipient New address to receive fees
     */
    function updateFeeRecipient(address _newFeeRecipient) external onlyOwner {
        require(_newFeeRecipient != address(0), "Invalid fee recipient");
        
        address oldRecipient = feeRecipient;
        feeRecipient = _newFeeRecipient;
        
        emit FeeRecipientUpdated(oldRecipient, _newFeeRecipient);
    }

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency withdraw function (only for stuck tokens)
     * @param _token Token address to withdraw
     * @param _amount Amount to withdraw
     */
    function emergencyWithdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Check if a stablecoin is supported
     * @param _token Token address to check
     * @return Whether the token is supported
     */
    function isStablecoinSupported(address _token) external view returns (bool) {
        return supportedStablecoins[_token];
    }

    /**
     * @dev Get current fee in basis points
     * @return Current fee percentage
     */
    function getCurrentFee() external view returns (uint256) {
        return feePercentage;
    }

    /**
     * @dev Check if transaction ID has been used
     * @param _transactionId Transaction ID to check
     * @return Whether the transaction has been completed
     */
    function isTransactionCompleted(bytes32 _transactionId) external view returns (bool) {
        return completedTransactions[_transactionId];
    }

    /**
     * @dev Get user's remittance stats
     * @param _user User address
     * @return totalSent Total amount sent by user
     * @return hasFirstBonus Whether user got first transfer bonus
     * @return hasMilestone1k Whether user reached $1000 milestone
     * @return hasMilestone5k Whether user reached $5000 milestone
     */
    function getUserStats(address _user) external view returns (
        uint256 totalSent,
        bool hasFirstBonus,
        bool hasMilestone1k,
        bool hasMilestone5k
    ) {
        return (
            totalSentByUser[_user],
            firstTransferBonus[_user],
            milestone1000[_user],
            milestone5000[_user]
        );
    }

    /**
     * @dev Get contract stats
     * @return totalTransactions Total number of completed transactions
     * @return currentFee Current fee percentage
     * @return currentRewardRate Current reward rate
     */
    function getContractStats() external view returns (
        uint256 totalTransactions, 
        uint256 currentFee,
        uint256 currentRewardRate
    ) {
        return (transactionCounter, feePercentage, rewardRate);
    }
}