//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../roles/OwnerWithdrawableUpgradable.sol";
import "../roles/OwnerPausableUpgradable.sol";

contract SignatureERC20Withdraw is OwnableUpgradeable, OwnerWithdrawableUpgradable, OwnerPausableUpgradable {
    /**
     * @notice erc20 address under withdraw
     */
    IERC20 public ad3Address;
    /**
     * @notice chainId on which this contract is deployed
     */
    uint256 public chainId;
    /**
     * @dev address - nounce - used
     * @notice used if true, not used if false
     **/
    mapping(address => mapping(uint256 => bool)) public addressNonceUsed;

    function initialize(address _ad3Address, uint256 _chainId)
        public
        initializer
    {
        __Ownable_init();
        __Pausable_init();
        ad3Address = IERC20(_ad3Address);
        chainId = _chainId;
    }

    function withdraw(
        address attester,
        address to,
        uint256 _chainId,
        uint256 amount,
        uint256 nounce,
        bytes memory signature
    ) external whenNotPaused returns (bool) {
        require(
            chainId == _chainId,
            "chainId in params should match the contract's chainId"
        );
        // cal message hash
        bytes32 hash = keccak256(
            abi.encodePacked(to, _chainId, amount, nounce)
        );
        // convert to EthSignedMessage hash
        bytes32 message = ECDSA.toEthSignedMessageHash(hash);
        // recover signer address
        address receivedAddress = ECDSA.recover(message, signature);
        // verify recevivedAddress with signer
        require(
            receivedAddress != address(0) && receivedAddress == attester,
            "signature not valid"
        );
        //TODO(ironman_ch): think over if add address as a part of key
        require(addressNonceUsed[to][nounce] == false, "nounce must not used");
        addressNonceUsed[to][nounce] = true;
        ad3Address.transfer(to, amount);
        return true;
    }
}
