// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./nft.sol";
import "./referral.sol";

contract MavroNodeSale is Ownable, ReentrancyGuard {
    IERC20 public paymentToken;
    NodeNFT public nftContract;
    MavroNewReferralsSystem public referralSystem;

    address public receiverAddress;

    uint256 public amountForCoFounder = 5000 * 10**18;
    uint256 public maxCoFounders = 50;
    uint256 public coFounderCount;

    address[] coFounders;

    uint256 public constant FIRST_NODES_DISCOUNT_COUNT = 300;
    uint256 public constant FIRST_NODES_DISCOUNT_PRICE = 200 ether;
    uint256 public constant BASE_NODE_PRICE = 300 ether;
    uint256 public constant PRICE_INCREMENT = 100 ether;
    uint256 public constant PRICE_INCREMENT_INTERVAL = 500;

    uint256 public constant MAX_NODE_AMOUNT = 11000;

    uint256 public totalNodesSold;
    uint256 public totalUsers;

    //Node Details
    struct UserNode {
        uint256 startId;
        uint256 endId;
        uint256 purchaseTime;
    }

    struct ActiveNode {
        uint256 nodeId;
        uint256 purchaseTime;
    }

    mapping(bytes32 => uint256) public batchBitmaps;
    mapping(uint256 => address) public nodeOwner;

    mapping(address => UserNode[]) public userNodes;
    mapping(address => uint256) public nodeCountOfAUser;
    mapping(address => string) public userCodes;
    mapping(string => address) public codeToAddr;

    event NodesPurchased(
        address indexed user,
        uint256 count,
        uint256 totalPrice
    );

    event NodeTransferred(uint256 indexed nodeId, address from, address to);
    event PriceTierUpdated(uint256 newPrice);

    constructor(
        address _paymentToken,
        address _nftContract,
        // address _rankingSystem,
        address _referralSystem,
        address _receiverAddr
    ) Ownable(msg.sender) {
        paymentToken = IERC20(_paymentToken);
        nftContract = NodeNFT(_nftContract);
        // rankingSystem = RankingSystem(_rankingSystem);
        referralSystem = MavroNewReferralsSystem(_referralSystem);
        receiverAddress = _receiverAddr;
    }

    function buyNodes(uint256 count, address referrer) external nonReentrant {
        require(count > 0, "Must buy at least 1 node");
        require(
            totalNodesSold + count <= MAX_NODE_AMOUNT,
            "Max node exceed, please reduce node count"
        );
        require(referrer != address(0), "Invalid Referrer");

        uint256 pricePerNode = getCurrentNodePrice();
        uint256 totalPrice = count * pricePerNode;

        if (totalNodesSold >= 1500 && count >= 3) {
            if (count < 5) {
                totalPrice -= 30 ether;
            } else if (count < 7) {
                totalPrice -= 50 ether;
            } else {
                totalPrice -= 100 ether;
            }
        }

        require(
            paymentToken.transferFrom(msg.sender, address(this), totalPrice),
            "Payment failed"
        );

        uint256 startId = totalNodesSold + 1;
        uint256 endId = totalNodesSold + count;

        userNodes[msg.sender].push(
            UserNode({
                startId: startId,
                endId: endId,
                purchaseTime: block.timestamp
            })
        );

        bytes32 batchKey = _getBatchKey(
            msg.sender,
            userNodes[msg.sender].length - 1
        );
        batchBitmaps[batchKey] = type(uint256).max;

        totalNodesSold += count;

        if (bytes(userCodes[msg.sender]).length == 0) {
            string memory code = generateRandomCode();
            userCodes[msg.sender] = code;
            codeToAddr[code] = msg.sender;
        }

        // Handle referral
        if (referrer != address(0) && referrer != msg.sender) {
            uint256 rewardPercentage = referralSystem
                .getEligibleRefRewardPercentage(referrer);

            uint256 refAmount = rewardPercentage > 0
                ? (totalPrice * rewardPercentage) / 10000
                : 0;

            require(
                paymentToken.transfer(address(referralSystem), refAmount),
                "Ref Transfer Failed"
            );
            referralSystem.recordReferral(
                msg.sender,
                count,
                referrer,
                totalPrice
            );

            totalPrice -= refAmount;
        }

        require(
            paymentToken.transfer(receiverAddress, totalPrice),
            "Fund Transfer Failed"
        );

        // Distribute NFTs based on purchase amount
        distributeNFTs(msg.sender, count);

        nodeCountOfAUser[msg.sender] += count;

        totalUsers++;
        emit NodesPurchased(msg.sender, count, totalPrice);
    }

    // Transfer single node
    function transferNode(uint256 nodeId, address to) external {
        (uint256 batchIndex, uint256 bitPosition) = _findNodeBatch(
            msg.sender,
            nodeId
        );
        bytes32 batchKey = _getBatchKey(msg.sender, batchIndex);

        require(batchBitmaps[batchKey] & (1 << bitPosition) != 0, "Not owner");

        // Remove from sender
        batchBitmaps[batchKey] &= ~(1 << bitPosition);
        nodeOwner[nodeId] = to;
        nodeCountOfAUser[msg.sender] -= 1;
        nodeCountOfAUser[to] += 1;

        // Add to recipient
        userNodes[to].push(
            UserNode({
                startId: nodeId,
                endId: nodeId,
                purchaseTime: block.timestamp
            })
        );

        // Set the bitmap for the recipient's new batch
        bytes32 recipientBatchKey = _getBatchKey(to, userNodes[to].length - 1);
        batchBitmaps[recipientBatchKey] = 1;

        referralSystem.recordNodeTransfer(msg.sender, to, 1);

        emit NodeTransferred(nodeId, msg.sender, to);
    }

    function becomeACoFounder(uint256 _amount) external nonReentrant {
        require(_amount >= amountForCoFounder, "Invalid Amount");
        require(coFounderCount <= maxCoFounders, "No seat left");

        require(
            paymentToken.transferFrom(msg.sender, receiverAddress, _amount),
            "Fund Transfer Failed"
        );
        referralSystem.addCoFounder(msg.sender);
        coFounderCount++;
        coFounders.push(msg.sender);
        nftContract.mintAngel(msg.sender, 20);
    }

    // View Function

    function getMyActiveNodes(address user)
        external
        view
        returns (ActiveNode[] memory)
    {
        UserNode[] storage batches = userNodes[user];
        uint256 activeCount;

        // First pass: count active nodes
        for (uint256 i = 0; i < batches.length; i++) {
            UserNode storage batch = batches[i];
            bytes32 batchKey = keccak256(abi.encodePacked(user, i));
            uint256 bitmap = batchBitmaps[batchKey];
            uint256 nodesInBatch = batch.endId - batch.startId + 1;

            // Only count bits up to the actual node count
            activeCount += _countSetBits(bitmap & ((1 << nodesInBatch) - 1));
        }

        ActiveNode[] memory activeNodes = new ActiveNode[](activeCount);
        uint256 counter;

        // Second pass: populate active nodes
        for (uint256 i = 0; i < batches.length; i++) {
            UserNode storage batch = batches[i];
            bytes32 batchKey = keccak256(abi.encodePacked(user, i));
            uint256 bitmap = batchBitmaps[batchKey];
            uint256 nodesInBatch = batch.endId - batch.startId + 1;

            uint256 currentId = batch.startId;
            uint256 remainingBitmap = bitmap & ((1 << nodesInBatch) - 1); // Mask unused bits

            while (remainingBitmap != 0) {
                if (remainingBitmap & 1 != 0) {
                    activeNodes[counter++] = ActiveNode({
                        nodeId: currentId,
                        purchaseTime: batch.purchaseTime
                    });
                }
                remainingBitmap >>= 1;
                currentId++;
            }
        }

        return activeNodes;
    }

    function idToAddress(string memory _id) public view returns (address) {
        return codeToAddr[_id];
    }

    function getCoFounderCount() public view returns (uint256) {
        return coFounderCount;
    }

    function addressToID(address _user) public view returns (string memory) {
        return userCodes[_user];
    }

    function getCurrentNodePrice() public view returns (uint256) {
        if (totalNodesSold < FIRST_NODES_DISCOUNT_COUNT) {
            return FIRST_NODES_DISCOUNT_PRICE;
        }

        if (totalNodesSold < 500) {
            return BASE_NODE_PRICE;
        }

        uint256 priceTier = (totalNodesSold - PRICE_INCREMENT_INTERVAL) /
            PRICE_INCREMENT_INTERVAL;
        return
            BASE_NODE_PRICE + PRICE_INCREMENT + (priceTier * PRICE_INCREMENT);
    }

    function getMyNodeCount(address _user) public view returns (uint256) {
        return nodeCountOfAUser[_user];
    }

    function distributeNFTs(address user, uint256 nodeCount) private {
        if (nodeCount >= 33) {
            nftContract.mintAngel(user, 30);
        } else if (nodeCount >= 15) {
            nftContract.mintAngel(user, 10);
        } else if (nodeCount >= 7) {
            nftContract.mintAngel(user, 5);
        } else if (nodeCount >= 3) {
            nftContract.mintAngel(user, 2);
        } else if (nodeCount >= 1) {
            nftContract.mintGolden(user, 1);
        }
    }

    //Internal functions

    function _countSetBits(uint256 n) internal pure returns (uint256) {
        uint256 count;
        while (n != 0) {
            n &= (n - 1); // Clear least significant bit
            count++;
        }
        return count;
    }

    function _getBatchKey(address user, uint256 batchIndex)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(user, batchIndex));
    }

    function _findNodeBatch(address user, uint256 nodeId)
        internal
        view
        returns (uint256 batchIndex, uint256 bitPosition)
    {
        UserNode[] storage batches = userNodes[user];

        // Binary search through batches
        uint256 low = 0;
        uint256 high = batches.length - 1;

        while (low <= high) {
            uint256 mid = (low + high) / 2;
            UserNode storage batch = batches[mid];

            if (nodeId < batch.startId) {
                high = mid - 1;
            } else if (nodeId > batch.endId) {
                low = mid + 1;
            } else {
                return (mid, nodeId - batch.startId);
            }
        }

        revert("Node not found");
    }

    function generateRandomCode() internal view returns (string memory) {
        uint256 randomNum = uint256(
            keccak256(abi.encodePacked(block.timestamp, msg.sender))
        );

        uint256 firstDigit = (randomNum % 9) + 1;
        uint256 remainingDigits = (randomNum % 100000);

        uint256 finalCode = (firstDigit * 100000) + remainingDigits;

        return Strings.toString(finalCode);
    }

    // Admin functions

    function setPaymentToken(address _token) external onlyOwner {
        paymentToken = IERC20(_token);
    }

    function addCoFounderManually(address _user) external onlyOwner {
        require(_user != address(0), "Invalid Address");
        referralSystem.addCoFounder(_user);
        coFounderCount++;
        coFounders.push(_user);
        nftContract.mintAngel(_user, 50);
    }

    function updateContracts(
        address _paymentToken,
        address _nftContract,
        address _referralSystem
    ) external onlyOwner {
        paymentToken = IERC20(_paymentToken);
        nftContract = NodeNFT(_nftContract);
        referralSystem = MavroNewReferralsSystem(_referralSystem);
    }

    function updateMaxCoFounder(uint256 _number) external onlyOwner {
        require(_number > 0, "Zero Amount");
        maxCoFounders = _number;
    }

    function updateAmountForCoFounder(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Zero Amount");
        amountForCoFounder = _amount;
    }

    function updateReceiver(address receiver) external onlyOwner {
        require(receiver != address(0), "Invalid Address");
        receiverAddress = receiver;
    }

    function withdrawFunds(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid Address");
        uint256 balance = paymentToken.balanceOf(address(this));
        paymentToken.transfer(recipient, balance);
    }
    
}
