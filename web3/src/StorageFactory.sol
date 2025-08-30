//SPDX-License-Identifier: MIT
 
 pragma solidity ^0.8.18;
import {SimpleStorage, SimpleStorage2} from "./SimpleStorage.sol";

contract StorageFactory{
    // type visiblity name
    SimpleStorage public simpleStorage;

    function createSimpleStorageContract() public {
        simpleStorage = new SimpleStorage();
    }
}