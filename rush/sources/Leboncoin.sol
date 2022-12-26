// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "./Escrow.sol";

contract Leboncoin is Ownable,ReentrancyGuard,PaymentSplitter{
    using Counters for Counters.Counter;
    Counters.Counter private productIds;
    address payable public contractOwner;
    address  devTeam = 0x09fCFD97B454ECA3FdB7b2b9a08f3263038516A9;
    address  comTeam = 0x7636c6D42042065fF52434fA8Fa9CF1a2004f582;
    address [] payees = [devTeam,comTeam];
    uint256 [] teamShares = [50,50];


    constructor() PaymentSplitter(payees, teamShares) payable {
    contractOwner = payable(msg.sender);
    }

    struct Product {
        uint id;
        string name;
        address payable owner;
        address payable escrow;
        uint256 price;
        productStatus status;
    }

    mapping(uint256 => Product) private idToProduct;
    mapping(address => bytes32) private buyersMerklRoot;

    enum productStatus { FOR_SALE, PENDING, SOLD }

    //The buyer get to choose the sale mode
    // mode Code is when the buyer sends a pass phrase allowing the seller to unlick the funds
    // mode CLASSIC allows the buyer to unlock the funds whenever he wants
    enum saleMode {CODE,CLASSIC}
    saleMode private mode;

    event ProductCreated (
    uint indexed id,
    string name,
    address owner,
    address escrow,
    uint256 price,
    productStatus status
    );

    function createProduct(string memory _name, uint256 _price) public payable nonReentrant returns(uint256){
        require(_price > 0, "Price must be at least 1 wei");
        productIds.increment();
        uint256 productId = productIds.current();
        idToProduct[productId] =  Product(
        productId,
        _name,
        payable(msg.sender),
        payable(address(0)),
        _price,
        productStatus.FOR_SALE
        );
        emit ProductCreated(productIds.current(), _name, msg.sender, address(0), _price, productStatus.FOR_SALE);
        return productId;
    }


    function buyProduct(uint256 _id) public payable nonReentrant{
        uint256 price = getProduct(_id).price;
        address payable owner = getProduct(_id).owner;
        Escrow escrow = new Escrow(msg.sender,owner,address(this));
        address  escrowAddr = escrow.returnAddr();

        //Check requirements to buy
        require(uint(idToProduct[_id].status) == 0, "Product not for sale or currently getting bought");
        require(msg.value >= price,"Not enough funds to purchase");
        require(msg.sender != owner, "can't buy your own product");
        require(escrowAddr != address(0), "escrow not deployed");

        //we set the escrow address of the product
        idToProduct[_id].escrow = payable(escrowAddr);
        //Transfer the amount to the escrow contract
        payable(escrowAddr).transfer(msg.value);
        escrow.deposit(payable(msg.sender));
        //Set product Status top pending
        idToProduct[_id].status = productStatus.PENDING;
    }

    function freeFundsWithcode(string memory _passphrase,bytes32[] calldata _proof, uint256 _id) public payable nonReentrant {
        address payable escrowAddr = payable(getEscrowAddr(_id));
        Escrow escrow = Escrow(escrowAddr);

        //Check if the product is on pending status & if a sale mode has been selected
        require(uint(idToProduct[_id].status) == 1, "A problem occured");
        require(uint(mode) == 0, "A problem occured");
        require(isCorrectPhrase(_passphrase,_proof,escrow.getBuyer()), "incorrect pass phrase");
        escrow.unlockFundsWithCode(payable(msg.sender));

        //Once the buyer confirms delivery, we set the new owner of the product & change the product status
        idToProduct[_id].status = productStatus.SOLD;
        idToProduct[_id].owner =payable(escrow.getBuyer());
        idToProduct[_id].escrow=payable(address(0));
    }

    function freeFundsBuyer(uint256 _id) public payable nonReentrant{
        address payable escrowAddr = payable(getEscrowAddr(_id));
        Escrow escrow = Escrow(escrowAddr);
        require(uint(idToProduct[_id].status) == 1, "A problem occured");
        require(uint(mode) == 1, "A problem occured");
        escrow.unlockFundsBuyer(payable(msg.sender));

        idToProduct[_id].status = productStatus.SOLD;
        idToProduct[_id].owner =payable(escrow.getBuyer());
        idToProduct[_id].escrow=payable(address(0));    
    }

    //Merkle Proof
    function isCorrectPhrase(string memory _passphrase, bytes32[] calldata proof,address _buyer) internal view returns(bool) {
        return _verify(_leaf(_passphrase), proof,_buyer);
    }

    function _leaf(string memory _passphrase) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(_passphrase));
    }

    function _verify(bytes32 leaf, bytes32[] memory proof,address _buyer) internal view returns(bool) {
        return MerkleProof.verify(proof, buyersMerklRoot[_buyer], leaf);
    }

    function setMerklRoot(bytes32 _root,uint256 _id) public{
        //if the msg sender is the buyer of the concerned product
        Escrow escrow = Escrow(payable(getEscrowAddr(_id)));
        require(msg.sender == escrow.getBuyer());
        buyersMerklRoot[msg.sender]=_root;
    }

    //Getters
    function getProduct(uint256 _id) public view returns(Product memory){
        return idToProduct[_id];
    }  

    function getEscrowAddr(uint256 _id) public view returns (address){
        return idToProduct[_id].escrow;
    }

    function getEscrowBalance(address _addr) public view returns(uint256){
        return _addr.balance;
    }

    function getProductbyOwner(address _addr) public view returns(Product memory){
        for(uint256 i=1;i<=productIds.current();i++){
            if(_addr == idToProduct[i].owner){
                return idToProduct[i];
            }
        }
    }

    //Setters
    function setSaleMode(uint256 _id, saleMode _choice) public {
        address escrowAddr = getEscrowAddr(_id);
        Escrow escrow = Escrow(payable(escrowAddr));
        address _buyer=escrow.getBuyer();

        //Check if msg sender is product buyer
        require(msg.sender == _buyer, "only product buyer allowed");
        mode = _choice;
    }

}

