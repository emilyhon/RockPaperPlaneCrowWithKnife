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
    event PlayMoveSuccess(bool success);
    event MoveRevealed(uint256 gameId, address player, uint256 moveInt);
    event GameResultAvailable(uint256 gameId, uint256 resultInt, address winner);
    event GamePaidOut(address winner, uint256 amount);

    error RPPCWK__NotEnoughFunds();
    error RPPCWK__NoGamesAvailable();
    error RPPCWK__GameFull();
    error RPPCWK__GameDoesNotExist();
    error RPPCWK__MoveAlreadyPlayed();
    error RPPCWK__InvalidPlayer();
    error RPPCWK__InvalidMove();
    error RPPCWK__MovesNotYetPlayed();
    error RPPCWK__EncryptedMoveMismatch();
    error RPPCWK__NoResultsToCalculate();
    error RPPCWK__TransferFailed();

    uint256 private constant MIN_BET = 0.0001 ether;
    uint256 private s_gameCounter;
    mapping(uint256 => Game) private s_games;
    mapping(uint256 => address) private s_results;
    
    /**
     * Deposit ether
     */
    receive() external payable {}

    modifier onlyPlayer(uint256 gameId) {
        if (msg.sender != s_games[gameId].player1 && msg.sender != s_games[gameId].player2) {
            revert RPPCWK__InvalidPlayer();
        }
        _;
    }

    modifier gameExists(uint256 gameId) {
        if (s_games[gameId].player1 == address(0)) {
            revert RPPCWK__GameDoesNotExist();
        }
        _;
    }
    
    /**
     * Start game function to initialize a game, the msg.value is the bet amount
     */
    function startGame() external payable returns (uint256){
        if (msg.value < MIN_BET) {
            revert RPPCWK__NotEnoughFunds();
        }

        s_games[s_gameCounter] = Game({
            player1: msg.sender,
            player2: address(0),
            encryptedMove1: 0,
            encryptedMove2: 0,
            move1: Move.None,
            move2: Move.None,
            bet: msg.value
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
            revert RPPCWK__NotEnoughFunds();
        }
        if (game.player2 != address(0)) {
            revert RPPCWK__GameFull();
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
                emit PlayMoveSuccess(false);
                revert RPPCWK__MoveAlreadyPlayed();
            }

            s_games[gameId].encryptedMove1 = encryptedMove;
        } else {
            if (s_games[gameId].move2 != Move.None) {
                emit PlayMoveSuccess(false);
                revert RPPCWK__MoveAlreadyPlayed();
            }

            s_games[gameId].encryptedMove2 = encryptedMove;
        }

        emit PlayMoveSuccess(true);
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
            revert RPPCWK__MovesNotYetPlayed();
        }

        if (msg.sender == game.player1) {
            if (game.encryptedMove1 != encryptedMove) {
                revert RPPCWK__EncryptedMoveMismatch();
            }
            game.move1 = Move(moveInt);
        } else {
            if (game.encryptedMove2 != encryptedMove) {
                revert RPPCWK__EncryptedMoveMismatch();
            }
            game.move2 = Move(moveInt);
        }

        emit MoveRevealed(gameId, msg.sender, moveInt);

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
            revert RPPCWK__NoResultsToCalculate();
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
            s_results[gameId] = address(this); // store contract address incase of draw
            emit GameResultAvailable(gameId, uint256(Result.Draw), address(0));
        } else if (
            (game.move1 == Move.Rock && game.move2 == Move.PaperPlane) ||
            (game.move1 == Move.PaperPlane && game.move2 == Move.CrowWithKnife) ||
            (game.move1 == Move.CrowWithKnife && game.move2 == Move.Rock)
        ) {
            // Player 2 wins
            payout = game.bet * 2;
            winner = payable(game.player2);
            pay(winner, payout);
            s_results[gameId] = winner;
            emit GameResultAvailable(gameId, uint256(Result.Player2Wins), winner);
        } else {
            // Player 1 wins
            payout = game.bet * 2;
            winner = payable(game.player1);
            pay(winner, payout);
            s_results[gameId] = winner;
            emit GameResultAvailable(gameId, uint256(Result.Player1Wins), winner);
        }

        // Reset game state
        delete s_games[gameId];
    }

    /**
     * Pay a given address a given amount
     * @param recipient The address to pay
     * @param amount The amount to pay
     */
    function pay(address payable recipient, uint256 amount) private {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert RPPCWK__TransferFailed();
        }

        emit GamePaidOut(recipient, amount);
    }

    /// Public view / pure functions
    function getResult(uint256 gameId) public view returns (address) {
        return s_results[gameId];
    }

    function getBetForGame(uint256 gameId) public view returns (uint256) {
        return s_games[gameId].bet;
    }

    function getGame(uint256 gameId) public view returns (
        address player1,
        address player2,
        bytes32 encryptedMove1,
        bytes32 encryptedMove2,
        Move move1,
        Move move2,
        uint256 bet
    ) {
        Game storage game = s_games[gameId];
        return (
            game.player1,
            game.player2,
            game.encryptedMove1,
            game.encryptedMove2,
            game.move1,
            game.move2,
            game.bet
        );
    }

    function getGameCounter() public view returns (uint256) {
        return s_gameCounter;
    }
}