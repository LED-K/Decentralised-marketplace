// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

contract Escrow{
    enum State { AWAITING_PAYMENT, AWAITING_DELIVERY, COMPLETE }
    
    State public currState;
    
    address public buyer;
    address payable public seller;
    address private store;

    constructor(address _buyer, address payable _seller,address _store){
        buyer = _buyer;
        seller = _seller;
        store = _store;
    }

    fallback() external payable {}

    receive() external payable {}

    function returnAddr() public view returns(address){
        return payable(address(this));
    }

    function getBuyer() public view returns(address){
        return buyer;
    }

    function deposit(address payable _buyer) external payable {
        require(buyer == _buyer, "only buyer allowed");
        require(currState == State.AWAITING_PAYMENT, "Already paid");
        currState = State.AWAITING_DELIVERY;
    }

    function unlockFundsWithCode(address payable _addr) external {
        require(seller == _addr, "only seller allowed");
        require(currState == State.AWAITING_DELIVERY, "Cannot confirm delivery");
        payable(store).transfer(address(this).balance/20);
        seller.transfer((address(this).balance)-(address(this).balance/20));
        currState = State.COMPLETE;
    }

    function unlockFundsBuyer(address payable _addr) external {
        require(_addr == buyer,"only buyer allowed");
        require(currState == State.AWAITING_DELIVERY, "Cannot confirm delivery");
        payable(store).transfer(address(this).balance/20);
        seller.transfer((address(this).balance)-(address(this).balance/20));
        currState = State.COMPLETE;
    }
    
}