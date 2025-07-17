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
}
