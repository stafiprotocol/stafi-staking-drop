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


        it("fis distribute amount should match totalReward", async function () {
            this.fisDrop = await this.FISDrop.deploy(this.fisToken.address)
            await this.fisDrop.deployed()
            const startBlock = "100"
            const rewardPerBlock = "10"
            const totalReward = "102"
            const claimableStartBlock = "130"
            const lockedEndBlock = "140"

            await this.fisDrop.add(this.lp.address, startBlock, rewardPerBlock, totalReward, claimableStartBlock, lockedEndBlock)

            await this.lp.connect(this.bob).approve(this.fisDrop.address, "1000")
            await this.fisDrop.connect(this.bob).deposit(0, "100")
            await time.advanceBlockTo("189")
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.bob.address)).to.equal("102")
        })

        it("should not distribute fis if no one deposit", async function () {
            this.fisDrop = await this.FISDrop.deploy(this.fisToken.address)
            await this.fisDrop.deployed()
            const startBlock = "100"
            const rewardPerBlock = "10"
            const totalReward = "102"
            const claimableStartBlock = "130"
            const lockedEndBlock = "140"

            await this.fisDrop.add(this.lp.address, startBlock, rewardPerBlock, totalReward, claimableStartBlock, lockedEndBlock)

            await this.lp.connect(this.bob).approve(this.fisDrop.address, "1000")
            await time.advanceBlockTo("189")

            const pool = await this.fisDrop.poolInfo("0")
            expect(pool.leftReward).to.equal("102")
        })

        it("should distribute fis properly for each staker", async function () {
            this.fisDrop = await this.FISDrop.deploy(this.fisToken.address)
            await this.fisDrop.deployed()
            const startBlock = "300"
            const rewardPerBlock = "1000"
            const totalReward = "700000"
            const claimableStartBlock = "400"
            const lockedEndBlock = "10000"

            await this.fisDrop.add(this.lp.address, startBlock, rewardPerBlock, totalReward, claimableStartBlock, lockedEndBlock)

            await this.lp.connect(this.alice).approve(this.fisDrop.address, "1000", {
                from: this.alice.address,
            })
            await this.lp.connect(this.bob).approve(this.fisDrop.address, "1000", {
                from: this.bob.address,
            })
            await this.lp.connect(this.carol).approve(this.fisDrop.address, "1000", {
                from: this.carol.address,
            })
            // Alice deposits 10 LPs at block 310
            await time.advanceBlockTo("309")
            await this.fisDrop.connect(this.alice).deposit(0, "10", { from: this.alice.address })
            // Bob deposits 20 LPs at block 314
            await time.advanceBlockTo("313")
            await this.fisDrop.connect(this.bob).deposit(0, "20", { from: this.bob.address })
            // Carol deposits 30 LPs at block 318
            await time.advanceBlockTo("317")
            await this.fisDrop.connect(this.carol).deposit(0, "30", { from: this.carol.address })
            // Alice deposits 10 more LPs at block 320. At this point:
            // Alice should have: 4*1000 + 4*1/3*1000 + 2*1/6*1000 = 5666
            // Bob should have: 4*2/3*1000 + 2*2/6*1000 = 3333
            // Carol should have: 2*3/6*1000 = 1000
            // Drop should have the remaining: 70000 - 10*1000 = 690000
            await time.advanceBlockTo("319")
            await this.fisDrop.connect(this.alice).deposit(0, "10", { from: this.alice.address })
            var pool = await this.fisDrop.poolInfo("0")
            expect(pool.leftReward).to.equal("690000")

            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.alice.address)).to.equal("5666")
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.bob.address)).to.equal("3333")
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.carol.address)).to.equal("1000")
            // Bob withdraws 5 LPs at block 330. At this point:
            // Alice should have: 4*1000 + 4*1/3*1000 + 2*1/6*1000 +10*2/7*1000= 8523
            // Bob should have: 4*2/3*1000 + 2*2/6*1000 + 10*2/7*1000 = 6190
            // Carol should have: 2*3/6*1000 + 10*3/7*1000 = 5285
            await time.advanceBlockTo("329")
            await this.fisDrop.connect(this.bob).withdraw(0, "5", { from: this.bob.address })
            pool = await this.fisDrop.poolInfo("0")
            expect(pool.leftReward).to.equal("680000")

            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.alice.address)).to.equal("8523")
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.bob.address)).to.equal("6190")
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.carol.address)).to.equal("5286")
            // Alice withdraws 20 LPs at block 340.
            // Bob withdraws 15 LPs at block 350.
            // Carol withdraws 30 LPs at block 360.
            await time.advanceBlockTo("339")
            await this.fisDrop.connect(this.alice).withdraw(0, "20", { from: this.alice.address })
            await time.advanceBlockTo("349")
            await this.fisDrop.connect(this.bob).withdraw(0, "15", { from: this.bob.address })
            await time.advanceBlockTo("359")
            await this.fisDrop.connect(this.carol).withdraw(0, "30", { from: this.carol.address })

            pool = await this.fisDrop.poolInfo("0")
            expect(pool.leftReward).to.equal("650000")
            // Alice should have: 5666 + 10*2/7*1000 + 10*2/6.5*1000 = 11600
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.alice.address)).to.equal("11600")
            // Bob should have: 6190 + 10*1.5/6.5 * 1000 + 10*1.5/4.5*1000 = 11831
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.bob.address)).to.equal("11831")
            // Carol should have: 2*3/6*1000 + 10*3/7*1000 + 10*3/6.5*1000 + 10*3/4.5*1000 + 10*1000 = 26568
            expect(await this.fisDrop.getUserCurrentTotalReward("0", this.carol.address)).to.equal("26568")
            // All of them should have 1000 LPs back.
            expect(await this.lp.balanceOf(this.alice.address)).to.equal("1000")
            expect(await this.lp.balanceOf(this.bob.address)).to.equal("1000")
            expect(await this.lp.balanceOf(this.carol.address)).to.equal("1000")
        })




    })

})