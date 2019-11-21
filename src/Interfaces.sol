pragma solidity 0.5.12;

contract GemLike {
    function allowance(address, address) public returns (uint);
    function approve(address, uint) public;
    function transfer(address, uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
    function balanceOf(address) public returns (uint);
    function deposit() public payable;
    function withdraw(uint) public;
}

contract SaiTubLike {
    function sai() public view returns (GemLike);
}

contract JoinLike {
    function dai() public view returns (GemLike);
}

contract OtcLike {
    function sellAllAmount(address, uint, address, uint) public returns (uint);
    function buyAllAmount(address, uint, address, uint) public returns (uint);
    function getPayAmount(address, address, uint) public returns (uint);
}

contract ScdMcdMigrationLike {
    function daiJoin() public view returns (JoinLike);
    function tub() public view returns (SaiTubLike);
    function swapSaiToDai(uint) public;
}
