// SPDX-License-Identifier: GPL

pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {
    address internal _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
    constructor() {
        _transferOwnership(_msgSender());
    }
    */

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    /*
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
    */
    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract ActivatedByOwner is Ownable {
    bool public active = true;

    function setActive(bool _active) public  onlyOwner
    {
        active = _active;
    }

    modifier onlyActive
    {
        require(active, "This contract is deactivated by owner");
        _;
    }
}

interface NFTInterface {
    function mintWithClass(uint256 classId) external returns (uint256 _newTokenID);
    function transfer(address _to, uint256 _tokenId, bytes calldata _data) external returns (bool);
    function addPropertyWithContent(uint256 _tokenId, string calldata _content) external;
}

interface TokenInterface {
    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface PriceFeed {
    function getPrice(address token) external view returns(uint256 price);
}

contract NFTMultiCurrencySaleSystem is ActivatedByOwner {

    event AuctionCreated(uint256 indexed tokenClassAuctionID, uint256 timestamp);
    event TokenSold(uint256 indexed tokenID, uint256 indexed tokenClassID, address indexed buyer);
    event NFTContractSet(address indexed newNFTContract, address indexed oldNFTContract);
    event TokenContractAdded(string indexed symbol, address indexed newTokenContract);
    event RevenueWithdrawal(uint256 amount);
    

    address public nft_contract;
    address public price_feed_contract = 0x9bFc3046ea26f8B09D3E85bd22AEc96C80D957e3;
    address public revenue = 0x01000B5fE61411C466b70631d7fF070187179Bbf; // This address has the rights to withdraw funds from the contact.
    mapping (string => address) public tokensList; //ERC20 or ERC223 available token list.

    struct NFTAuctionClass
    {
        uint256 max_supply;
        uint256 amount_sold;
        uint256 start_timestamp;
        uint256 duration;
        uint256 priceInWei;
        string[] configuratin_properties;
    }

    mapping (uint256 => NFTAuctionClass) public auctions; // Mapping from classID (at NFT contract) to set of variables
                                                          //  defining the auction for this token class.
    constructor()
    {
        _owner = msg.sender;
    }

    function createNFTAuction(
        uint256 _classID, 
        uint256 _max_supply, 
        uint256 _start_timestamp, 
        uint256 _duration, 
        uint256 _priceInWEI,
        uint256 _already_sold 
        ) public onlyOwner
    {
        auctions[_classID].max_supply      = _max_supply;
        auctions[_classID].amount_sold     = _already_sold; 
        auctions[_classID].start_timestamp = _start_timestamp;
        auctions[_classID].duration        = _duration;
        auctions[_classID].priceInWei      = _priceInWEI;

        emit AuctionCreated(_classID, block.timestamp);
    }

    function setRevenueAddress(address payable _revenue_address) public  onlyOwner {
        revenue = _revenue_address;
    }

    function setPriceFeedAddress(address payable _price_feed_contract) public  onlyOwner {
        price_feed_contract = _price_feed_contract;
    }

    function setNFTContract(address _nftContract) public onlyOwner
    {
        emit NFTContractSet(_nftContract, nft_contract);

        nft_contract = _nftContract;
    }

    function AddTokenContract(string memory _symbol, address _token_contract) public onlyOwner
    {
        emit TokenContractAdded(_symbol, _token_contract);

        tokensList[_symbol] = _token_contract;
    }

    function buyNFTwithToken(uint256 _classID, string memory _token_symbol,uint256 _currency_amount) public onlyActive
    {
        // WARNING!
        // This function does not refund overpaid amount at the moment.
        // TODO

        uint256 toUSD = _currency_amount * PriceFeed(price_feed_contract).getPrice(tokensList[_token_symbol]);

        require(toUSD >= auctions[_classID].priceInWei, "Insufficient funds");
        require(auctions[_classID].amount_sold < auctions[_classID].max_supply, "This sale has already sold all allocated NFTs");
        require(block.timestamp < auctions[_classID].start_timestamp + auctions[_classID].duration, "This sale already expired");
        require(block.timestamp > auctions[_classID].start_timestamp, "This sale is not yet started");
        require(auctions[_classID].priceInWei != 0, "Min price is not configured by the owner");

        TokenInterface(tokensList[_token_symbol]).transferFrom(msg.sender, revenue, _currency_amount);

        uint256 _mintedId = NFTInterface(nft_contract).mintWithClass(_classID);
        auctions[_classID].amount_sold++;

        NFTInterface(nft_contract).transfer(msg.sender, _mintedId, "");

        emit TokenSold(_mintedId, _classID, msg.sender);
    }

    function buyNFTwithCoin(uint256 _classID, string memory _token_symbol,uint256 _currency_amount) public payable onlyActive
    {
        // WARNING!
        // This function does not refund overpaid amount at the moment.
        // TODO

        require(_currency_amount*10e18 == msg.value, "_currency_amount and msg.value do not match");

        uint256 toUSD = _currency_amount * PriceFeed(price_feed_contract).getPrice(tokensList[_token_symbol]);

        require(toUSD >= auctions[_classID].priceInWei, "Insufficient funds");
        require(auctions[_classID].amount_sold < auctions[_classID].max_supply, "This sale has already sold all allocated NFTs");
        require(block.timestamp < auctions[_classID].start_timestamp + auctions[_classID].duration, "This sale already expired");
        require(block.timestamp > auctions[_classID].start_timestamp, "This sale is not yet started");
        require(auctions[_classID].priceInWei != 0, "Min price is not configured by the owner");

        uint256 _mintedId = NFTInterface(nft_contract).mintWithClass(_classID);
        auctions[_classID].amount_sold++;

        NFTInterface(nft_contract).transfer(msg.sender, _mintedId, "");

        emit TokenSold(_mintedId, _classID, msg.sender);
    }

    function withdrawRevenue() public onlyOwner
    {
        emit RevenueWithdrawal(address(this).balance);

        payable(revenue).transfer(address(this).balance);
    }
}
