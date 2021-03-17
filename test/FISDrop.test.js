const { ethers } = require("hardhat")
const { expect } = require("chai")
const { time } = require("./utilities")

describe("FISDrop", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.alice = this.signers[0]
        this.bob = this.signers[1]
        this.carol = this.signers[2]
        this.dev = this.signers[3]
        this.minter = this.signers[4]

        this.FISDrop = await ethers.getContractFactory("FISDrop")
        this.FISToken = await ethers.getContractFactory("FISToken")
        this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
    })

    beforeEach(async function () {
        this.fisToken = await this.FISToken.deploy()
        await this.fisToken.deployed()

    })

    it("should set correct state variables", async function () {
        this.fisDrop = await this.FISDrop.deploy(this.fisToken.address)
        await this.fisDrop.deployed()
        const fis = await this.fisDrop.FIS()
        expect(fis).to.equal(this.fisToken.address)
    })

    context("With ERC/LP token added to the field", function () {
        beforeEach(async function () {
            this.lp = await this.ERC20Mock.deploy("LPToken", "LP", "10000000000")

            await this.lp.transfer(this.alice.address, "1000")

            await this.lp.transfer(this.bob.address, "1000")

            await this.lp.transfer(this.carol.address, "1000")

            this.lp2 = await this.ERC20Mock.deploy("LPToken2", "LP2", "10000000000")

            await this.lp2.transfer(this.alice.address, "1000")

            await this.lp2.transfer(this.bob.address, "1000")

            await this.lp2.transfer(this.carol.address, "1000")
        })

        it("should allow emergency withdraw", async function () {
            const startBlock = "10"
            const rewardPerBlock = "10"
            const totalReward = "100"
            const claimableStartBlock = "30"
            const lockedEndBlock = "40"

            this.fisDrop = await this.FISDrop.deploy(this.fisToken.address)
            await this.fisDrop.deployed()

            await this.fisDrop.add(this.lp.address, startBlock, rewardPerBlock, totalReward, claimableStartBlock, lockedEndBlock)

            await this.lp.connect(this.bob).approve(this.fisDrop.address, "1000")

            await this.fisDrop.connect(this.bob).deposit(0, "100")

            expect(await this.lp.balanceOf(this.bob.address)).to.equal("900")

            await this.fisDrop.connect(this.bob).emergencyWithdraw(0)

            expect(await this.lp.balanceOf(this.bob.address)).to.equal("1000")
        })

        it("should give out fis only after startBock", async function () {
            this.fisDrop = await this.FISDrop.deploy(this.fisToken.address)
            await this.fisDrop.deployed()
            const startBlock = "100"
            const rewardPerBlock = "10"
            const totalReward = "100"
            const claimableStartBlock = "130"
            const lockedEndBlock = "140"

            await this.fisDrop.add(this.lp.address, startBlock, rewardPerBlock, totalReward, claimableStartBlock, lockedEndBlock)

            await this.lp.connect(this.bob).approve(this.fisDrop.address, "1000")
            await this.fisDrop.connect(this.bob).deposit(0, "100")
            await time.advanceBlockTo("89")

            await this.fisDrop.connect(this.bob).deposit(0, "0") // block 90
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.bob.address)).to.equal("0")
            await time.advanceBlockTo("94")

            await this.fisDrop.connect(this.bob).deposit(0, "0") // block 95
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.bob.address)).to.equal("0")
            await time.advanceBlockTo("99")

            await this.fisDrop.connect(this.bob).deposit(0, "0") // block 100
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.bob.address)).to.equal("0")
            await time.advanceBlockTo("100")

            await this.fisDrop.connect(this.bob).deposit(0, "0") // block 101
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.bob.address)).to.equal("10")

            await time.advanceBlockTo("104")
            await this.fisDrop.connect(this.bob).deposit(0, "0") // block 105

            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.bob.address)).to.equal("50")
        })


    })

})