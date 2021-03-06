pragma solidity ^0.5.12;

import "ds-token/token.sol";
import "ds-math/math.sol";

import {DssDeployTestBase} from "dss-deploy/DssDeploy.t.base.sol";
import {AuthGemJoin} from "dss-deploy/join.sol";
import {DssCdpManager} from "dss-cdp-manager/DssCdpManager.sol";
import {Spotter} from "dss/spot.sol";
import {DSProxy, DSProxyFactory} from "ds-proxy/proxy.sol";
import {WETH9_} from "ds-weth/weth9.sol";
import {DSToken} from "ds-token/token.sol";
import {OasisDirectProxy } from "./test-deps/OasisDirectProxy.sol";

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
    function getPayAmount(address, address, uint) public view returns (uint);
}

contract MockOTC {
    address payToken; 
    uint payAmt; 
    address buyToken;
    uint minBuyAmt;
    bool selling;
    uint buyAmt;

    constructor(address _payToken, uint _payAmt, address _buyToken, uint _minBuyAmt, bool _selling, uint _buyAmt) public {
        payToken = _payToken;
        payAmt = _payAmt;
        buyToken = _buyToken;
        minBuyAmt = _minBuyAmt;
        selling = _selling;
        buyAmt = _buyAmt;
    }

    function sellAllAmount(address _payToken, uint _payAmt, address _buyToken, uint _minBuyAmt) public returns (uint) {
        require(payToken == _payToken);
        require(payAmt == _payAmt);
        require(buyToken == _buyToken);
        require(minBuyAmt == _minBuyAmt);
        require(selling == true);

        TokenInterface(_payToken).transferFrom(msg.sender, address(this), _payAmt);
        TokenInterface(_buyToken).transfer(msg.sender, _minBuyAmt);

        return _minBuyAmt;
    }

    function buyAllAmount(address _buyToken, uint _buyAmt, address _payToken, uint _maxPayAmt) public returns (uint) {
        require(buyToken == _buyToken);
        require(buyAmt == _buyAmt);
        require(payToken == _payToken);
        require(minBuyAmt == _maxPayAmt);
        require(selling == false);

        TokenInterface(_payToken).transferFrom(msg.sender, address(this), _maxPayAmt);
        TokenInterface(_buyToken).transfer(msg.sender, _buyAmt);

        return _maxPayAmt;
    }

    function getPayAmount(address _payToken, address _buyToken, uint _buyAmt) public view returns (uint) {
        require(payToken == _payToken);
        require(buyToken == _buyToken);
        require(buyAmt == _buyAmt);
        
        return minBuyAmt;
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
    bytes32             cup;
    bytes32             cup2;
    OasisDirectMigrateProxyActions oasisDirectMigrateProxyActions;
    OasisDirectProxy oasisDirectProxy;
    DSToken dgd;

    function setUp() public {
        super.setUp();

        // Deploy MCD
        deployKeepAuth();

        // Deploy SCD
        deploySai();

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
        oasisDirectProxy = new OasisDirectProxy();

        dgd = new DSToken("DGD");
        dgd.mint(0.1 ether);
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

    function testSellAllAmountAndMigrateSai() public {
        uint256 amount = 100 ether;
        uint256 minAmount = 0.1 ether;

        MockOTC mockOTC = new MockOTC(address(dai), amount, address(dgd), minAmount, true, 0);
        dgd.transfer(address(mockOTC), minAmount);

        assertEq(sai.balanceOf(address(this)), amount);
        assertEq(dai.balanceOf(address(this)), 0);

        sai.approve(address(oasisDirectMigrateProxyActions), amount);

        oasisDirectMigrateProxyActions.sellAllAmountAndMigrateSai(
            address(mockOTC),
            address(dai),
            amount,
            address(dgd),
            minAmount,
            address(migration)
        );

        // sender should have no dai, sai and at least min requested DGD
        assertEq(sai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dgd.balanceOf(address(this)), minAmount);

        // no tokens at proxy contract
        assertEq(sai.balanceOf(address(oasisDirectMigrateProxyActions)), 0);
        assertEq(dai.balanceOf(address(oasisDirectMigrateProxyActions)), 0);
        assertEq(dgd.balanceOf(address(oasisDirectMigrateProxyActions)), 0);

        // OTC should get DAI (mocked impl)
        assertEq(sai.balanceOf(address(mockOTC)), 0);
        assertEq(dai.balanceOf(address(mockOTC)), amount);
        assertEq(dgd.balanceOf(address(mockOTC)), 0);
    }

    function testSellAllAmountBuyEthAndMigrateSai() public {
        uint256 amount = 100 ether;
        uint256 minAmount = 0.1 ether;

        MockOTC mockOTC = new MockOTC(address(dai), amount, address(weth), minAmount, true, 0);
        weth.deposit.value(amount)();
        weth.transfer(address(mockOTC), amount);
        uint initialBalance = address(this).balance;

        assertEq(sai.balanceOf(address(this)), amount);
        assertEq(dai.balanceOf(address(this)), 0);
        
        sai.approve(address(oasisDirectMigrateProxyActions), amount);
        
        oasisDirectMigrateProxyActions.sellAllAmountBuyEthAndMigrateSai(
            address(mockOTC),
            address(dai),
            amount,
            address(weth),
            minAmount,
            address(migration)
        );

        // sender should have no dai, sai and at least min requested eth
        assertEq(sai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(address(this).balance, initialBalance + minAmount);

        // no tokens at proxy contract
        assertEq(sai.balanceOf(address(oasisDirectMigrateProxyActions)), 0);
        assertEq(dai.balanceOf(address(oasisDirectMigrateProxyActions)), 0);
        assertEq(address(oasisDirectMigrateProxyActions).balance, 0);

        // OTC should get DAI (mocked impl)
        assertEq(sai.balanceOf(address(mockOTC)), 0);
        assertEq(dai.balanceOf(address(mockOTC)), amount);
        assertEq(address(mockOTC).balance, 0);
    }

    function testBuyAllAmountAndMigrateSai() public {
        uint256 amount = 0.1 ether;
        uint256 maxAmount = 100 ether;

        MockOTC mockOTC = new MockOTC(address(dai), amount, address(dgd), maxAmount, false, amount);
        dgd.transfer(address(mockOTC), amount);

        assertEq(sai.balanceOf(address(this)), maxAmount);
        assertEq(dai.balanceOf(address(this)), 0);

        sai.approve(address(oasisDirectMigrateProxyActions), maxAmount);

        oasisDirectMigrateProxyActions.buyAllAmountAndMigrateSai(
            address(mockOTC),
            address(dgd),
            amount,
            address(dai),
            maxAmount,
            address(migration)
        );

        // sender should have no dai, sai and at least min requested DGD
        assertEq(sai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dgd.balanceOf(address(this)), amount);

        // no tokens at proxy contract
        assertEq(sai.balanceOf(address(oasisDirectMigrateProxyActions)), 0);
        assertEq(dai.balanceOf(address(oasisDirectMigrateProxyActions)), 0);
        assertEq(dgd.balanceOf(address(oasisDirectMigrateProxyActions)), 0);

        // OTC should get DAI (mocked impl)
        assertEq(sai.balanceOf(address(mockOTC)), 0);
        assertEq(dai.balanceOf(address(mockOTC)), maxAmount);
        assertEq(dgd.balanceOf(address(mockOTC)), 0);
    }

    function testBuyAllAmountBuyEthAndMigrateSai() public {
        uint256 amount = 0.1 ether;
        uint256 maxAmount = 100 ether;

        MockOTC mockOTC = new MockOTC(address(dai), amount, address(weth), maxAmount, false, amount);
        weth.deposit.value(amount)();
        weth.transfer(address(mockOTC), amount);
        uint initialBalance = address(this).balance;

        assertEq(sai.balanceOf(address(this)), maxAmount);

        sai.approve(address(oasisDirectMigrateProxyActions), maxAmount);

        oasisDirectMigrateProxyActions.buyAllAmountBuyEthAndMigrateSai(
            address(mockOTC),
            address(weth),
            amount,
            address(dai),
            maxAmount,
            address(migration)
        );

        // sender should have no dai, sai and at least min requested eth
        assertEq(sai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(address(this).balance, initialBalance + amount);

        // no tokens at proxy contract
        assertEq(sai.balanceOf(address(oasisDirectMigrateProxyActions)), 0);
        assertEq(dai.balanceOf(address(oasisDirectMigrateProxyActions)), 0);
        assertEq(address(oasisDirectMigrateProxyActions).balance, 0);

        // OTC should get DAI (mocked impl)
        assertEq(sai.balanceOf(address(mockOTC)), 0);
        assertEq(dai.balanceOf(address(mockOTC)), maxAmount);
        assertEq(address(mockOTC).balance, 0);
    }
}
