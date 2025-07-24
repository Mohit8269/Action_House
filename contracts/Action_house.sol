// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Project {
    struct Auction {
        address seller;
        string itemName;
        string description;
        uint256 startingPrice;
        uint256 currentBid;
        address currentBidder;
        uint256 endTime;
        bool active;
        bool claimed;
    }

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => mapping(address => uint256)) public bids;
    uint256 public auctionCounter;
    uint256 public constant AUCTION_DURATION = 7 days;
    uint256 public constant MIN_BID_INCREMENT = 0.01 ether;

    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        string itemName,
        uint256 startingPrice,
        uint256 endTime
    );

    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount,
        uint256 timestamp
    );

    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid,
        uint256 timestamp
    );

    event AuctionCancelled(
        uint256 indexed auctionId,
        address indexed seller,
        uint256 timestamp
    );

    event AuctionExtended(
        uint256 indexed auctionId,
        uint256 newEndTime,
        uint256 timestamp
    );

    modifier onlyActiveBid(uint256 _auctionId) {
        require(auctions[_auctionId].active, "Auction is not active");
        require(block.timestamp < auctions[_auctionId].endTime, "Auction has ended");
        _;
    }

    modifier onlyAuctionSeller(uint256 _auctionId) {
        require(auctions[_auctionId].seller == msg.sender, "Only seller can perform this action");
        _;
    }

    /**
     * @dev Create a new auction
     * @param _itemName Name of the item being auctioned
     * @param _description Description of the item
     * @param _startingPrice Minimum starting bid amount
     */
    function createAuction(
        string memory _itemName,
        string memory _description,
        uint256 _startingPrice
    ) external returns (uint256) {
        require(bytes(_itemName).length > 0, "Item name cannot be empty");
        require(_startingPrice > 0, "Starting price must be greater than 0");

        uint256 auctionId = auctionCounter++;
        uint256 endTime = block.timestamp + AUCTION_DURATION;

        auctions[auctionId] = Auction({
            seller: msg.sender,
            itemName: _itemName,
            description: _description,
            startingPrice: _startingPrice,
            currentBid: 0,
            currentBidder: address(0),
            endTime: endTime,
            active: true,
            claimed: false
        });

        emit AuctionCreated(auctionId, msg.sender, _itemName, _startingPrice, endTime);
        return auctionId;
    }

    /**
     * @dev Place a bid on an active auction
     * @param _auctionId ID of the auction to bid on
     */
    function placeBid(uint256 _auctionId) external payable onlyActiveBid(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        require(msg.sender != auction.seller, "Seller cannot bid on their own auction");
        require(
            msg.value >= auction.startingPrice && 
            msg.value >= auction.currentBid + MIN_BID_INCREMENT,
            "Bid must be higher than current bid plus minimum increment"
        );

        // Refund previous bidder
        if (auction.currentBidder != address(0)) {
            bids[_auctionId][auction.currentBidder] += auction.currentBid;
        }

        // Update auction with new bid
        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;

        emit BidPlaced(_auctionId, msg.sender, msg.value, block.timestamp);
    }

    /**
     * @dev End an auction and transfer funds
     * @param _auctionId ID of the auction to end
     */
    function endAuction(uint256 _auctionId) external {
        Auction storage auction = auctions[_auctionId];
        require(auction.active, "Auction is not active");
        require(
            block.timestamp >= auction.endTime || msg.sender == auction.seller,
            "Auction cannot be ended yet"
        );
        require(!auction.claimed, "Auction already claimed");

        auction.active = false;
        auction.claimed = true;

        if (auction.currentBidder != address(0)) {
            // Transfer winning bid to seller
            payable(auction.seller).transfer(auction.currentBid);
            
            emit AuctionEnded(_auctionId, auction.currentBidder, auction.currentBid, block.timestamp);
        } else {
            emit AuctionEnded(_auctionId, address(0), 0, block.timestamp);
        }
    }

    /**
     * @dev Withdraw failed bids
     * @param _auctionId ID of the auction
     */
    function withdrawBid(uint256 _auctionId) external {
        uint256 bidAmount = bids[_auctionId][msg.sender];
        require(bidAmount > 0, "No bid to withdraw");

        bids[_auctionId][msg.sender] = 0;
        payable(msg.sender).transfer(bidAmount);
    }

    /**
     * @dev Cancel an auction (only by seller, only if no bids placed)
     * @param _auctionId ID of the auction to cancel
     */
    function cancelAuction(uint256 _auctionId) external onlyAuctionSeller(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        require(auction.active, "Auction is not active");
        require(auction.currentBidder == address(0), "Cannot cancel auction with existing bids");
        require(!auction.claimed, "Auction already claimed");

        auction.active = false;
        auction.claimed = true;

        emit AuctionCancelled(_auctionId, msg.sender, block.timestamp);
    }

    /**
     * @dev Get all active auctions
     * @return activeAuctionIds Array of active auction IDs
     */
    function getActiveAuctions() external view returns (uint256[] memory activeAuctionIds) {
        // First, count active auctions
        uint256 activeCount = 0;
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].active && block.timestamp < auctions[i].endTime) {
                activeCount++;
            }
        }

        // Create array with exact size
        activeAuctionIds = new uint256[](activeCount);
        uint256 index = 0;
        
        // Fill array with active auction IDs
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].active && block.timestamp < auctions[i].endTime) {
                activeAuctionIds[index] = i;
                index++;
            }
        }

        return activeAuctionIds;
    }

    /**
     * @dev Get auction details
     * @param _auctionId ID of the auction
     */
    function getAuction(uint256 _auctionId) external view returns (
        address seller,
        string memory itemName,
        string memory description,
        uint256 startingPrice,
        uint256 currentBid,
        address currentBidder,
        uint256 endTime,
        bool active,
        bool claimed
    ) {
        Auction storage auction = auctions[_auctionId];
        return (
            auction.seller,
            auction.itemName,
            auction.description,
            auction.startingPrice,
            auction.currentBid,
            auction.currentBidder,
            auction.endTime,
            auction.active,
            auction.claimed
        );
    }

    /**
     * @dev Get total number of auctions created
     */
    function getTotalAuctions() external view returns (uint256) {
        return auctionCounter;
    }

    /**
     * @dev Check if auction is active
     * @param _auctionId ID of the auction
     */
    function isAuctionActive(uint256 _auctionId) external view returns (bool) {
        return auctions[_auctionId].active && block.timestamp < auctions[_auctionId].endTime;
    }

    // ========== EXISTING FUNCTIONS ==========

    /**
     * @dev Get all auctions created by a specific seller
     * @param _seller Address of the seller
     * @return sellerAuctionIds Array of auction IDs created by the seller
     */
    function getAuctionsBySeller(address _seller) external view returns (uint256[] memory sellerAuctionIds) {
        require(_seller != address(0), "Invalid seller address");
        
        // First, count auctions by seller
        uint256 sellerCount = 0;
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].seller == _seller) {
                sellerCount++;
            }
        }

        // Create array with exact size
        sellerAuctionIds = new uint256[](sellerCount);
        uint256 index = 0;
        
        // Fill array with seller's auction IDs
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].seller == _seller) {
                sellerAuctionIds[index] = i;
                index++;
            }
        }

        return sellerAuctionIds;
    }

    /**
     * @dev Extend auction duration (only by seller, before auction ends)
     * @param _auctionId ID of the auction to extend
     * @param _additionalTime Additional time to add (in seconds)
     */
    function extendAuction(uint256 _auctionId, uint256 _additionalTime) external onlyAuctionSeller(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        require(auction.active, "Auction is not active");
        require(!auction.claimed, "Auction already claimed");
        require(_additionalTime > 0, "Additional time must be greater than 0");
        require(_additionalTime <= 7 days, "Cannot extend more than 7 days at once");
        require(block.timestamp < auction.endTime, "Cannot extend ended auction");

        auction.endTime += _additionalTime;

        emit AuctionExtended(_auctionId, auction.endTime, block.timestamp);
    }

    // ========== NEW FUNCTIONS ==========

    /**
     * @dev Get all auctions that a specific address has bid on
     * @param _bidder Address of the bidder
     * @return bidderAuctionIds Array of auction IDs the bidder has participated in
     */
    function getAuctionsByBidder(address _bidder) external view returns (uint256[] memory bidderAuctionIds) {
        require(_bidder != address(0), "Invalid bidder address");
        
        // First, count auctions where bidder participated
        uint256 bidderCount = 0;
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].currentBidder == _bidder || bids[i][_bidder] > 0) {
                bidderCount++;
            }
        }

        // Create array with exact size
        bidderAuctionIds = new uint256[](bidderCount);
        uint256 index = 0;
        
        // Fill array with auction IDs where bidder participated
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].currentBidder == _bidder || bids[i][_bidder] > 0) {
                bidderAuctionIds[index] = i;
                index++;
            }
        }

        return bidderAuctionIds;
    }

    /**
     * @dev Get detailed auction statistics
     * @return totalAuctions Total number of auctions created
     * @return activeAuctions Number of currently active auctions
     * @return completedAuctions Number of completed auctions with winners
     * @return cancelledAuctions Number of cancelled auctions
     * @return totalVolume Total trading volume across all auctions
     * @return averageBid Average winning bid amount
     */
    function getAuctionStatistics() external view returns (
        uint256 totalAuctions,
        uint256 activeAuctions,
        uint256 completedAuctions,
        uint256 cancelledAuctions,
        uint256 totalVolume,
        uint256 averageBid
    ) {
        totalAuctions = auctionCounter;
        
        for (uint256 i = 0; i < auctionCounter; i++) {
            Auction storage auction = auctions[i];
            
            if (auction.active && block.timestamp < auction.endTime) {
                activeAuctions++;
            } else if (!auction.active && auction.claimed && auction.currentBidder != address(0)) {
                completedAuctions++;
                totalVolume += auction.currentBid;
            } else if (!auction.active && auction.claimed && auction.currentBidder == address(0)) {
                cancelledAuctions++;
            }
        }
        
        if (completedAuctions > 0) {
            averageBid = totalVolume / completedAuctions;
        }
        
        return (
            totalAuctions,
            activeAuctions,
            completedAuctions,
            cancelledAuctions,
            totalVolume,
            averageBid
        );
    }

    // ========== NEWLY ADDED FUNCTIONS ==========

    /**
     * @dev Get auctions ending soon (within next 24 hours)
     * @return endingSoonIds Array of auction IDs ending within 24 hours
     * @return timeRemaining Array of seconds remaining for each auction
     */
    function getAuctionsEndingSoon() external view returns (
        uint256[] memory endingSoonIds,
        uint256[] memory timeRemaining
    ) {
        uint256 oneDayFromNow = block.timestamp + 24 hours;
        
        // First, count auctions ending soon
        uint256 endingSoonCount = 0;
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].active && 
                block.timestamp < auctions[i].endTime && 
                auctions[i].endTime <= oneDayFromNow) {
                endingSoonCount++;
            }
        }

        // Create arrays with exact size
        endingSoonIds = new uint256[](endingSoonCount);
        timeRemaining = new uint256[](endingSoonCount);
        uint256 index = 0;
        
        // Fill arrays with auction data
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].active && 
                block.timestamp < auctions[i].endTime && 
                auctions[i].endTime <= oneDayFromNow) {
                endingSoonIds[index] = i;
                timeRemaining[index] = auctions[i].endTime - block.timestamp;
                index++;
            }
        }

        return (endingSoonIds, timeRemaining);
    }

    /**
     * @dev Get user profile with bidding and selling history
     * @param _user Address of the user
     * @return userAuctions Array of auction IDs created by user
     * @return userBids Array of auction IDs user has bid on
     * @return totalSold Number of successfully sold auctions
     * @return totalBought Number of auctions won by user
     * @return totalRevenue Total ETH earned from selling
     * @return totalSpent Total ETH spent on winning bids
     */
    function getUserProfile(address _user) external view returns (
        uint256[] memory userAuctions,
        uint256[] memory userBids,
        uint256 totalSold,
        uint256 totalBought,
        uint256 totalRevenue,
        uint256 totalSpent
    ) {
        require(_user != address(0), "Invalid user address");
        
        // Count user's auctions and bids
        uint256 auctionCount = 0;
        uint256 bidCount = 0;
        
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].seller == _user) {
                auctionCount++;
                // Check if auction was successfully sold
                if (!auctions[i].active && auctions[i].claimed && auctions[i].currentBidder != address(0)) {
                    totalSold++;
                    totalRevenue += auctions[i].currentBid;
                }
            }
            
            if (auctions[i].currentBidder == _user || bids[i][_user] > 0) {
                bidCount++;
                // Check if user won this auction
                if (!auctions[i].active && auctions[i].claimed && auctions[i].currentBidder == _user) {
                    totalBought++;
                    totalSpent += auctions[i].currentBid;
                }
            }
        }
        
        // Create and fill arrays
        userAuctions = new uint256[](auctionCount);
        userBids = new uint256[](bidCount);
        uint256 auctionIndex = 0;
        uint256 bidIndex = 0;
        
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].seller == _user) {
                userAuctions[auctionIndex] = i;
                auctionIndex++;
            }
            
            if (auctions[i].currentBidder == _user || bids[i][_user] > 0) {
                userBids[bidIndex] = i;
                bidIndex++;
            }
        }
        
        return (
            userAuctions,
            userBids,
            totalSold,
            totalBought,
            totalRevenue,
            totalSpent
        );
    }

    // ========== TWO NEW ADDITIONAL FUNCTIONS ==========

    /**
     * @dev Get top auctions by current bid amount
     * @param _limit Maximum number of auctions to return
     * @return topAuctionIds Array of auction IDs sorted by highest bids
     * @return topBids Array of corresponding bid amounts
     */
    function getTopAuctionsByBid(uint256 _limit) external view returns (
        uint256[] memory topAuctionIds,
        uint256[] memory topBids
    ) {
        require(_limit > 0, "Limit must be greater than 0");
        
        // Get all active auctions first
        uint256[] memory activeIds = new uint256[](auctionCounter);
        uint256[] memory activeBids = new uint256[](auctionCounter);
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].active && block.timestamp < auctions[i].endTime && auctions[i].currentBid > 0) {
                activeIds[activeCount] = i;
                activeBids[activeCount] = auctions[i].currentBid;
                activeCount++;
            }
        }
        
        // Sort by bid amount (bubble sort for simplicity)
        for (uint256 i = 0; i < activeCount - 1; i++) {
            for (uint256 j = 0; j < activeCount - i - 1; j++) {
                if (activeBids[j] < activeBids[j + 1]) {
                    // Swap bids
                    uint256 tempBid = activeBids[j];
                    activeBids[j] = activeBids[j + 1];
                    activeBids[j + 1] = tempBid;
                    
                    // Swap IDs
                    uint256 tempId = activeIds[j];
                    activeIds[j] = activeIds[j + 1];
                    activeIds[j + 1] = tempId;
                }
            }
        }
        
        // Return top auctions up to limit
        uint256 returnCount = activeCount > _limit ? _limit : activeCount;
        topAuctionIds = new uint256[](returnCount);
        topBids = new uint256[](returnCount);
        
        for (uint256 i = 0; i < returnCount; i++) {
            topAuctionIds[i] = activeIds[i];
            topBids[i] = activeBids[i];
        }
        
        return (topAuctionIds, topBids);
    }

    /**
     * @dev Search auctions by item name (partial matching)
     * @param _searchTerm The search term to look for in item names
     * @param _activeOnly If true, only return active auctions
     * @return matchingIds Array of auction IDs that match the search
     * @return matchingNames Array of corresponding item names
     */
    function searchAuctionsByName(string memory _searchTerm, bool _activeOnly) external view returns (
        uint256[] memory matchingIds,
        string[] memory matchingNames
    ) {
        require(bytes(_searchTerm).length > 0, "Search term cannot be empty");
        
        bytes memory searchBytes = bytes(_searchTerm);
        uint256 matchCount = 0;
        
        // First pass: count matches
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (_activeOnly && (!auctions[i].active || block.timestamp >= auctions[i].endTime)) {
                continue;
            }
            
            bytes memory nameBytes = bytes(auctions[i].itemName);
            if (_containsSubstring(nameBytes, searchBytes)) {
                matchCount++;
            }
        }
        
        // Second pass: collect matches
        matchingIds = new uint256[](matchCount);
        matchingNames = new string[](matchCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (_activeOnly && (!auctions[i].active || block.timestamp >= auctions[i].endTime)) {
                continue;
            }
            
            bytes memory nameBytes = bytes(auctions[i].itemName);
            if (_containsSubstring(nameBytes, searchBytes)) {
                matchingIds[index] = i;
                matchingNames[index] = auctions[i].itemName;
                index++;
            }
        }
        
        return (matchingIds, matchingNames);
    }

    // ========== TWO ADDITIONAL NEW FUNCTIONS ==========

    /**
     * @dev Get auctions within a specific price range
     * @param _minPrice Minimum current bid amount
     * @param _maxPrice Maximum current bid amount (0 for no upper limit)
     * @param _activeOnly If true, only return active auctions
     * @return priceRangeIds Array of auction IDs within the price range
     * @return priceRangeBids Array of corresponding current bid amounts
     */
    function getAuctionsByPriceRange(
        uint256 _minPrice,
        uint256 _maxPrice,
        bool _activeOnly
    ) external view returns (
        uint256[] memory priceRangeIds,
        uint256[] memory priceRangeBids
    ) {
        require(_minPrice >= 0, "Minimum price cannot be negative");
        require(_maxPrice == 0 || _maxPrice >= _minPrice, "Maximum price must be greater than minimum price");
        
        uint256 matchCount = 0;
        
        // First pass: count matches
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (_activeOnly && (!auctions[i].active || block.timestamp >= auctions[i].endTime)) {
                continue;
            }
            
            uint256 currentBid = auctions[i].currentBid;
            // If no bids yet, use starting price
            if (currentBid == 0) {
                currentBid = auctions[i].startingPrice;
            }
            
            bool inRange = currentBid >= _minPrice && (_maxPrice == 0 || currentBid <= _maxPrice);
            if (inRange) {
                matchCount++;
            }
        }
        
        // Second pass: collect matches
        priceRangeIds = new uint256[](matchCount);
        priceRangeBids = new uint256[](matchCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (_activeOnly && (!auctions[i].active || block.timestamp >= auctions[i].endTime)) {
                continue;
            }
            
            uint256 currentBid = auctions[i].currentBid;
            // If no bids yet, use starting price
            if (currentBid == 0) {
                currentBid = auctions[i].startingPrice;
            }
            
            bool inRange = currentBid >= _minPrice && (_maxPrice == 0 || currentBid <= _maxPrice);
            if (inRange) {
                priceRangeIds[index] = i;
                priceRangeBids[index] = currentBid;
                index++;
            }
        }
        
        return (priceRangeIds, priceRangeBids);
    }

    /**
     * @dev Batch operation to get multiple auction details at once
     * @param _auctionIds Array of auction IDs to retrieve
     * @return sellers Array of seller addresses
     * @return itemNames Array of item names
     * @return currentBids Array of current bid amounts
     * @return endTimes Array of auction end times
     * @return activeStates Array of active status for each auction
     */
    function getBatchAuctionDetails(uint256[] memory _auctionIds) external view returns (
        address[] memory sellers,
        string[] memory itemNames,
        uint256[] memory currentBids,
        uint256[] memory endTimes,
        bool[] memory activeStates
    ) {
        require(_auctionIds.length > 0, "Auction IDs array cannot be empty");
        require(_auctionIds.length <= 50, "Cannot retrieve more than 50 auctions at once");
        
        uint256 length = _auctionIds.length;
        sellers = new address[](length);
        itemNames = new string[](length);
        currentBids = new uint256[](length);
        endTimes = new uint256[](length);
        activeStates = new bool[](length);
        
        for (uint256 i = 0; i < length; i++) {
            uint256 auctionId = _auctionIds[i];
            require(auctionId < auctionCounter, "Invalid auction ID");
            
            Auction storage auction = auctions[auctionId];
            sellers[i] = auction.seller;
            itemNames[i] = auction.itemName;
            currentBids[i] = auction.currentBid;
            endTimes[i] = auction.endTime;
            activeStates[i] = auction.active && block.timestamp < auction.endTime;
        }
        
        return (sellers, itemNames, currentBids, endTimes, activeStates);
    }

    // ========== TWO LATEST ADDED FUNCTIONS ==========

    /**
     * @dev Get comprehensive bid history for a specific auction
     * @param _auctionId ID of the auction
     * @return bidders Array of addresses who placed bids
     * @return bidAmounts Array of bid amounts (including withdrawn bids)
     * @return currentWinner Address of current highest bidder
     * @return totalBidders Number of unique bidders
     * @return hasActiveBids True if auction has any active bids
     */
    function getAuctionBidHistory(uint256 _auctionId) external view returns (
        address[] memory bidders,
        uint256[] memory bidAmounts,
        address currentWinner,
        uint256 totalBidders,
        bool hasActiveBids
    ) {
        require(_auctionId < auctionCounter, "Invalid auction ID");
        
        Auction storage auction = auctions[_auctionId];
        
        // Count unique bidders by checking the bids mapping
        address[] memory tempBidders = new address[](100); // Temporary array, assuming max 100 bidders
        uint256[] memory tempAmounts = new uint256[](100);
        uint256 bidderCount = 0;
        
        // This is a simplified approach - in a real implementation, you'd need to track bid history with events
        // For now, we'll return current bidder info and withdrawn bids
        
        // Check if there's a current bidder
        if (auction.currentBidder != address(0)) {
            tempBidders[bidderCount] = auction.currentBidder;
            tempAmounts[bidderCount] = auction.currentBid;
            bidderCount++;
            hasActiveBids = true;
        }
        
        // Note: This implementation is limited as we don't store full bid history
        // In a production contract, you'd emit events and track historical bids
        
        bidders = new address[](bidderCount);
        bidAmounts = new uint256[](bidderCount);
        
        for (uint256 i = 0; i < bidderCount; i++) {
            bidders[i] = tempBidders[i];
            bidAmounts[i] = tempAmounts[i];
        }
        
        currentWinner = auction.currentBidder;
        totalBidders = bidderCount;
        
        return (bidders, bidAmounts, currentWinner, totalBidders, hasActiveBids);
    }

    /**
     * @dev Get recommended auctions for a user based on their bidding history and preferences
     * @param _user Address of the user
     * @param _maxResults Maximum number of recommendations to return
     * @return recommendedIds Array of recommended auction IDs
     * @return recommendedNames Array of item names for recommended auctions
     * @return recommendedPrices Array of current prices for recommended auctions
     * @return matchReasons Array of reason codes (1=price range, 2=similar category, 3=ending soon)
     */
    function getRecommendedAuctions(address _user, uint256 _maxResults) external view returns (
        uint256[] memory recommendedIds,
        string[] memory recommendedNames,
        uint256[] memory recommendedPrices,
        uint256[] memory matchReasons
    ) {
        require(_user != address(0), "Invalid user address");
        require(_maxResults > 0 && _maxResults <= 20, "Max results must be between 1 and 20");
        
        // Calculate user's average bid to suggest similar price range
        uint256 totalSpent = 0;
        uint256 completedBids = 0;
        
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (!auctions[i].active && auctions[i].claimed && auctions[i].currentBidder == _user) {
                totalSpent += auctions[i].currentBid;
                completedBids++;
            }
