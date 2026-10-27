import Foundation
import Testing
@testable import CabinCore

/// The complaint the Music screen shows. The reading of what is playing runs every few seconds, and a complaint about a
/// command the person just sent (no device ready, say) must not be wiped by the first read that follows it.
@Suite struct SpotifyProblemBoardTests {
    @Test func startsWithNothingToShow() {
        #expect(SpotifyProblemBoard().current == nil)
    }

    @Test func aFailedCommandIsShown() {
        var board = SpotifyProblemBoard()
        board.commandFailed(.noActiveDevice)
        #expect(board.current == .noActiveDevice)
    }

    /// With no device ready Spotify answers every read with "nothing is playing". That is not a sign the problem went away.
    @Test func aReadWithNothingPlayingKeepsTheNoDeviceComplaint() {
        var board = SpotifyProblemBoard()
        board.commandFailed(.noActiveDevice)
        board.readAnswered(playing: false)
        board.readAnswered(playing: false)
        #expect(board.current == .noActiveDevice)
    }

    @Test func somethingPlayingClearsTheComplaint() {
        var board = SpotifyProblemBoard()
        board.commandFailed(.noActiveDevice)
        board.readAnswered(playing: true)
        #expect(board.current == nil)
    }

    @Test func aLaterSuccessfulCommandClearsIt() {
        var board = SpotifyProblemBoard()
        board.commandFailed(.noActiveDevice)
        board.commandSucceeded()
        #expect(board.current == nil)
    }

    @Test func refusalsStayUntilSomethingChanges() {
        for failure in [SpotifyFailure.premiumRequired, .notAllowed, .http(400)] {
            var board = SpotifyProblemBoard()
            board.commandFailed(failure)
            board.readAnswered(playing: false)
            #expect(board.current == failure)
        }
    }

    @Test func connectionTroubleClearsOnTheNextAnsweredRead() {
        for failure in [SpotifyFailure.offline, .rateLimited(retryAfter: 3)] {
            var board = SpotifyProblemBoard()
            board.commandFailed(failure)
            #expect(board.current == failure)
            board.readAnswered(playing: false)
            #expect(board.current == nil)
        }
    }

    @Test func aFailedReadIsShownUntilTheNextAnsweredRead() {
        var board = SpotifyProblemBoard()
        board.readFailed(.offline)
        #expect(board.current == .offline)
        board.readAnswered(playing: false)
        #expect(board.current == nil)
    }

    @Test func aFailedReadReplacesAnEarlierComplaint() {
        var board = SpotifyProblemBoard()
        board.commandFailed(.noActiveDevice)
        board.readFailed(.offline)
        #expect(board.current == .offline)
        board.readAnswered(playing: false)
        #expect(board.current == nil)
    }

    @Test func clearRemovesTheComplaintWhateverItWas() {
        var board = SpotifyProblemBoard()
        board.commandFailed(.noActiveDevice)
        board.clear()
        #expect(board.current == nil)
        board.readAnswered(playing: false)
        #expect(board.current == nil)
    }
}
