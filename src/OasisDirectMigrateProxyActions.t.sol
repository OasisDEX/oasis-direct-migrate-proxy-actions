pragma solidity 0.5.11;

import "ds-token/token.sol";
import "ds-math/math.sol";

import {DssDeployTestBase} from "dss-deploy/DssDeploy.t.base.sol";
import {AuthGemJoin} from "dss-deploy/join.sol";
import {DssCdpManager} from "dss-cdp-manager/DssCdpManager.sol";
import {Spotter} from "dss/spot.sol";
import {DSProxy, DSProxyFactory} from "ds-proxy/proxy.sol";
import {WETH9_} from "ds-weth/weth9.sol";
import {DSToken} from "ds-token/token.sol";

import {
    GemFab, VoxFab, DevVoxFab, TubFab, DevTubFab, TapFab,
    TopFab, DevTopFab, MomFab, DadFab, DevDadFab, DaiFab,
    DSValue, DSRoles, DevTub, SaiTap, SaiMom
} from "sai/sai.t.base.sol";

import {ScdMcdMigration} from "scd-mcd-migration/ScdMcdMigration.sol";
import {MigrationProxyActions} from "scd-mcd-migration/MigrationProxyActions.sol";
import {OasisDirectMigrateProxyActions} from "./OasisDirectMigrateProxyActions.sol";

contract MockSaiPip {
    function peek() public pure returns (bytes32 val, bool zzz) {
        val = bytes32(uint(1 ether)); // 1 DAI = 1 SAI
        zzz = true;
    }
}

contract TokenInterface {
    function balanceOf(address) public returns (uint);
    function allowance(address, address) public returns (uint);
    function approve(address, uint) public;
    function transfer(address,uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
    function deposit() public payable;
    function withdraw(uint) public;
}

contract OtcInterface {
    function sellAllAmount(address, uint, address, uint) public returns (uint);
    function buyAllAmount(address, uint, address, uint) public returns (uint);
    function getPayAmount(address, address, uint) public returns (uint);
}

contract MockOasisDirectProxy {
    address otc;
    address payToken; 
    uint payAmt; 
    address buyToken;
    uint minBuyAmt;
    uint buyAmt;

    constructor(address _otc, address _payToken, uint _payAmt, address _buyToken, uint _minBuyAmt, uint _buyAmt) public {
        otc = _otc;
        payToken = _payToken;
        payAmt = _payAmt;
        buyToken = _buyToken;
        minBuyAmt = _minBuyAmt;
        buyAmt = _buyAmt;
    }

    function sellAllAmount(address _otc, address _payToken, uint _payAmt, address _buyToken, uint _minBuyAmt) public returns (uint) {
        require(otc == _otc);
        require(payToken == _payToken);
        require(payAmt == _payAmt);
        require(buyToken == _buyToken);
        require(minBuyAmt == _minBuyAmt);

        return buyAmt;
    }

    function buyAllAmount(address _otc, address _payToken, uint _payAmt, address _buyToken, uint _minBuyAmt) public returns (uint payAmt) {

    }
}

contract OasisDirectMigrateProxyActionsTest is DssDeployTestBase, DSMath {
    DevTub              tub;
    DSToken             sai;
    DSToken             skr;
    ScdMcdMigration     migration;
    DssCdpManager       manager;
    AuthGemJoin         saiJoin;
    Spotter             saiPrice;
    DSProxy             proxy;
    MigrationProxyActions             migrationProxyActions;
    address             otc;
    bytes32             cup;
    bytes32             cup2;
    OasisDirectMigrateProxyActions oasisDirectMigrateProxyActions;
    DSToken dgd;

    function setUp() public {
        super.setUp();

        // Deploy MCD
        deployKeepAuth();

        // Deploy SCD
        deploySai();

        // not existing otc
        otc = address(0);


        // Create CDP Manager
        manager = new DssCdpManager(address(vat));

        // Create SAI collateral
        saiJoin = new AuthGemJoin(address(vat), "SAI", address(sai));
        dssDeploy.deployCollateral("SAI", address(saiJoin), address(new MockSaiPip()));
        this.file(address(spotter), "SAI", "mat", uint(1)); // The lowest collateralization ratio possible
        spotter.poke("SAI");
        this.file(address(vat), bytes32("SAI"), bytes32("line"), 10000 * 10 ** 45);

        // Create Migration Contract
        migration = new ScdMcdMigration(
            address(tub),
            address(manager),
            address(saiJoin),
            address(ethJoin),
            address(daiJoin)
        );

        // Create Proxy Factory, proxy and migration proxy actions
        DSProxyFactory factory = new DSProxyFactory();
        proxy = DSProxy(factory.build());
        migrationProxyActions = new MigrationProxyActions();

        // Deposit, approve and join 20 ETH == 20 SKR
        weth.deposit.value(20 ether)();
        weth.approve(address(tub), 20 ether);
        tub.join(20 ether);

        // Generate CDP for migrate
        cup = tub.open();
        tub.lock(cup, 1 ether);
        tub.draw(cup, 99.999999999999999999 ether);
        tub.give(cup, address(proxy));

        // Generate some extra SAI in another CDP
        cup2 = tub.open();
        tub.lock(cup2, 1 ether);
        tub.draw(cup2, 0.000000000000000001 ether);

        // Give access to the special authed SAI collateral to Migration contract
        saiJoin.rely(address(migration));

        oasisDirectMigrateProxyActions = new OasisDirectMigrateProxyActions();

        dgd = new DSToken("DGD");
    }

    function deploySai() public {
        GemFab gemFab = new GemFab();
        DevVoxFab voxFab = new DevVoxFab();
        DevTubFab tubFab = new DevTubFab();
        TapFab tapFab = new TapFab();
        DevTopFab topFab = new DevTopFab();
        MomFab momFab = new MomFab();
        DevDadFab dadFab = new DevDadFab();

        DaiFab daiFab = new DaiFab(gemFab, VoxFab(address(voxFab)), TubFab(address(tubFab)), tapFab, TopFab(address(topFab)), momFab, DadFab(address(dadFab)));

        daiFab.makeTokens();
        DSValue pep = new DSValue();
        daiFab.makeVoxTub(ERC20(address(weth)), gov, pipETH, pep, address(123));
        daiFab.makeTapTop();
        daiFab.configParams();
        daiFab.verifyParams();
        DSRoles authority = new DSRoles();
        authority.setRootUser(address(this), true);
        daiFab.configAuth(authority);

        sai = DSToken(daiFab.sai());
        skr = DSToken(daiFab.skr());
        tub = DevTub(address(daiFab.tub()));

        sai.approve(address(tub));
        skr.approve(address(tub));
        weth.approve(address(tub), uint(-1));
        gov.approve(address(tub));

        SaiTap tap = SaiTap(daiFab.tap());

        sai.approve(address(tap));
        skr.approve(address(tap));

        pep.poke(bytes32(uint(300 ether)));

        SaiMom mom = SaiMom(daiFab.mom());

        mom.setCap(10000 ether);
        mom.setAxe(10 ** 27);
        mom.setMat(10 ** 27);
        mom.setTax(10 ** 27);
        mom.setFee(1.000001 * 10 ** 27);
        mom.setTubGap(1 ether);
        mom.setTapGap(1 ether);
    }

    function _swapSaiToDai(uint amount) internal {
        sai.approve(address(migration), amount);
        migration.swapSaiToDai(amount);
    }

    function testDirectMigrate() public {
        uint256 amount = 100 ether;
        uint256 minAmount = 0.1 ether;

        MockOasisDirectProxy oasisDirectProxy = new MockOasisDirectProxy(otc, address(dai), amount, address(dgd), minAmount, amount);

        assertEq(sai.balanceOf(address(this)), amount);
        assertEq(dai.balanceOf(address(this)), 0);


        sai.approve(address(oasisDirectMigrateProxyActions), amount);
        
        oasisDirectMigrateProxyActions.sellAllAmountAndMigrateSai(
            address(migrationProxyActions),
            address(migration),
            address(oasisDirectProxy),
            address(dai),
            address(otc),
            amount,
            address(dgd),
            minAmount
        );

        assertEq(sai.balanceOf(address(this)), 0 ether);
        // assertEq(dai.balanceOf(address(this)), 0 ether);
        // introduce mock OTC not mock OasisDirectProxy
    }
}
