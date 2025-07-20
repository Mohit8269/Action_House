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
}
