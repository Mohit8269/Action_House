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

    /**
     * @dev Helper function to check if a string contains a substring (case-insensitive)
     * @param _text The text to search in
     * @param _substring The substring to search for
     * @return found True if substring is found in text
     */
    function _containsSubstring(bytes memory _text, bytes memory _substring) private pure returns (bool found) {
        if (_substring.length > _text.length) {
            return false;
        }
        
        if (_substring.length == 0) {
            return true;
        }
        
        for (uint256 i = 0; i <= _text.length - _substring.length; i++) {
            bool match = true;
            for (uint256 j = 0; j < _substring.length; j++) {
                // Convert to lowercase for case-insensitive comparison
                bytes1 textChar = _toLower(_text[i + j]);
                bytes1 subChar = _toLower(_substring[j]);
                
                if (textChar != subChar) {
                    match = false;
                    break;
                }
            }
            if (match) {
                return true;
            }
        }
        
        return false;
    }

    /**
     * @dev Helper function to convert a character to lowercase
     * @param _char The character to convert
     * @return The lowercase version of the character
     */
    function _toLower(bytes1 _char) private pure returns (bytes1) {
        if (_char >= 0x41 && _char <= 0x5A) {
            return bytes1(uint8(_char) + 32);
        }
        return _char;
    }
}
