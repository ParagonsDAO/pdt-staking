import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20('Mock Token', 'MOCK') {}

    function mint(address account_, uint256 amount_) external {
        _mint(account_, amount_);
    }
}