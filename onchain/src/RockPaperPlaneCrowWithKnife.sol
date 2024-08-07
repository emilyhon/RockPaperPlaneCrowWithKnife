// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RockPaperPlaneCrowWithKnife is ReentrancyGuard {
    // @dev Information related to a game
    struct Game {
        address player1;
        address player2;
        bytes32 encryptedMove1;
        bytes32 encryptedMove2;
        Move move1;
        Move move2;
        uint256 bet;
    }

    enum Move {None, Rock, PaperPlane, CrowWithKnife}
    enum Result {None, Draw, Player1Wins, Player2Wins}

    event GameStarted(uint256 gameId);

    error RPPCWF__NotEnoughFunds();
    error RPPCWF__NoGamesAvailable();
    error RPPCWF__GameFull();
    error RPPCWF__GameDoesNotExist();
    error RPPCWF__MoveAlreadyPlayed();
    error RPPCWF__InvalidPlayer();
    error RPPCWF__InvalidMove();
    error RPPCWF__MovesNotYetPlayed();
    error RPPCWF__EncryptedMoveMismatch();
    error RPPCWF__NoResultsToCalculate();

    uint256 private constant MIN_BET = 0.0001 ether;
    uint256 private s_gameCounter;
    mapping(uint256 => Game) private s_games;
    
    /**
     * Deposit ether
     */
    receive() external payable {}

    modifier onlyPlayer(uint256 gameId) {
        if (msg.sender != s_games[gameId].player1 && msg.sender != s_games[gameId].player2) {
            revert RPPCWF__InvalidPlayer();
        }
        _;
    }

    modifier gameExists(uint256 gameId) {
        if (s_games[gameId].player1 == address(0)) {
            revert RPPCWF__GameDoesNotExist();
        }
        _;
    }
    
    /**
     * Start game function to initialize a game
     * @param bet The amount of ether to bet
     */
    function startGame(uint256 bet) external payable returns (uint256){
        if (msg.value < MIN_BET || msg.value != bet) {
            revert RPPCWF__NotEnoughFunds();
        }

        s_games[s_gameCounter] = Game({
            player1: msg.sender,
            player2: address(0),
            encryptedMove1: 0,
            encryptedMove2: 0,
            move1: Move.None,
            move2: Move.None,
            bet: bet
        });

        emit GameStarted(s_gameCounter);

        s_gameCounter++;

        return s_gameCounter - 1;
    }

    /**
     * Join game function to register as the second player in a game
     * @param gameId The id of the game to join
     */
    function joinGame(uint256 gameId) external payable gameExists(gameId){
        Game storage game = s_games[gameId];
        if (msg.value != game.bet) {
            revert RPPCWF__NotEnoughFunds();
        }
        if (game.player2 != address(0)) {
            revert RPPCWF__GameFull();
        }

        game.player2 = msg.sender;
    }

    /**
     * Register a move for a game
     * @param gameId The id of the game to play
     * @param encryptedMove The encrypted move to play
     */
    function playMove(uint256 gameId, bytes32 encryptedMove) external onlyPlayer(gameId) gameExists(gameId) {
        if (msg.sender == s_games[gameId].player1) {
            if (s_games[gameId].move1 != Move.None) {
                revert RPPCWF__MoveAlreadyPlayed();
            }

            s_games[gameId].encryptedMove1 = encryptedMove;
        } else {
            if (s_games[gameId].move2 != Move.None) {
                revert RPPCWF__MoveAlreadyPlayed();
            }

            s_games[gameId].encryptedMove2 = encryptedMove;
        }
    }

    /**
     * Reveal your move for a game
     * @param gameId The id of the game to reveal
     * @param moveInt The actual move
     * @param encryptedMove The encrypted move
     */
    function reveal(uint256 gameId, uint256 moveInt, bytes32 encryptedMove) external onlyPlayer(gameId) gameExists(gameId){
        Game storage game = s_games[gameId];

        if (game.encryptedMove1 == 0 || game.encryptedMove2 == 0) {
            revert RPPCWF__MovesNotYetPlayed();
        }

        if (msg.sender == game.player1) {
            if (game.encryptedMove1 != encryptedMove) {
                revert RPPCWF__EncryptedMoveMismatch();
            }
            game.move1 = Move(moveInt);
        } else {
            if (game.encryptedMove2 != encryptedMove) {
                revert RPPCWF__EncryptedMoveMismatch();
            }
            game.move2 = Move(moveInt);
        }

        if (game.move1 != Move.None && game.move2 != Move.None) {
            calculateResult(gameId);
        }
    }

    /**
     * Calculate the result of a game and pays winner
     * @param gameId The id of the game to calculate
     */
    function calculateResult(uint256 gameId) private nonReentrant gameExists(gameId){
        if (s_games[gameId].move1 == Move.None || s_games[gameId].move2 == Move.None) {
            revert RPPCWF__NoResultsToCalculate();
        }

        Game storage game = s_games[gameId];
        address payable winner;
        uint256 payout;

        if (game.move1 == game.move2) {
            payout = game.bet;
            winner = payable(game.player1);
            pay(winner, payout);
            winner = payable(game.player2);
            pay(winner, payout);
        } else if (
            (game.move1 == Move.Rock && game.move2 == Move.PaperPlane) ||
            (game.move1 == Move.PaperPlane && game.move2 == Move.CrowWithKnife) ||
            (game.move1 == Move.CrowWithKnife && game.move2 == Move.Rock)
        ) {
            // Player 2 wins
            payout = game.bet * 2;
            winner = payable(game.player2);
            pay(winner, payout);
        } else {
            // Player 1 wins
            payout = game.bet * 2;
            winner = payable(game.player1);
            pay(winner, payout);
        }

        // Reset game state
        delete s_games[gameId];
    }

    /**
     * Pay a given address a given amount
     * @param addr The address to pay
     * @param amount The amount to pay
     */
    function pay(address payable addr, uint256 amount) private {
        if (address(this).balance < amount) {
            revert RPPCWF__NotEnoughFunds();
        }

        addr.transfer(amount);
    }

    /**
     * Return first character of a given string
     */
    function getFirstChar(string memory str) private pure returns (uint256) {
        bytes memory b = bytes(str);
        if (b.length == 0) {
            return 0;
        }
        bytes1 firstByte = b[0];
        if (firstByte == 0x31) {
            return 1;
        } else if (firstByte == 0x32) {
            return 2;
        } else if (firstByte == 0x33) {
            return 3;
        } else {
            return 0;
        }
    }
}