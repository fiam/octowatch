import XCTest
@testable import Octowatch

final class AttentionViewerPresentationPolicyTests: XCTestCase {
    func testActorPresentationPersonalizesViewerLabel() {
        let actor = AttentionActor(login: "alberto", avatarURL: nil)

        let presentation = AttentionViewerPresentationPolicy.actorPresentation(
            for: actor,
            viewerLogin: "alberto"
        )

        XCTAssertEqual(presentation.label, "you")
        XCTAssertFalse(presentation.showsBotBadge)
    }

    func testActorPresentationMarksBotAccounts() {
        let actor = AttentionActor(
            login: "github-merge-queue[bot]",
            avatarURL: nil,
            isBot: true
        )

        let presentation = AttentionViewerPresentationPolicy.actorPresentation(
            for: actor,
            viewerLogin: nil
        )

        XCTAssertEqual(presentation.label, "github-merge-queue")
        XCTAssertTrue(presentation.showsBotBadge)
    }

    func testUpdatePresentationKeepsBotActorSeparateFromDetail() {
        let actor = AttentionActor(
            login: "github-merge-queue[bot]",
            avatarURL: nil,
            isBot: true
        )

        let presentation = AttentionViewerPresentationPolicy.updatePresentation(
            actor: actor,
            detail: "Trigger Terraform",
            viewerLogin: nil
        )

        XCTAssertEqual(presentation.actor?.label, "github-merge-queue")
        XCTAssertTrue(presentation.actor?.showsBotBadge ?? false)
        XCTAssertEqual(presentation.detail, "Trigger Terraform")
    }

    func testUpdatePresentationStripsRawBotLoginPrefix() {
        let actor = AttentionActor(
            login: "github-merge-queue[bot]",
            avatarURL: nil,
            isBot: true
        )

        let presentation = AttentionViewerPresentationPolicy.updatePresentation(
            actor: actor,
            detail: "github-merge-queue[bot] · Trigger Terraform",
            viewerLogin: nil
        )

        XCTAssertEqual(presentation.actor?.label, "github-merge-queue")
        XCTAssertEqual(presentation.detail, "Trigger Terraform")
    }

    func testUpdatePresentationStripsDuplicatedActorPrefix() {
        let actor = AttentionActor(login: "alberto", avatarURL: nil)

        let presentation = AttentionViewerPresentationPolicy.updatePresentation(
            actor: actor,
            detail: "alberto · Trigger Terraform",
            viewerLogin: "alberto"
        )

        XCTAssertEqual(presentation.actor?.label, "you")
        XCTAssertEqual(presentation.detail, "Trigger Terraform")
    }

    func testListContextSubtitleStripsActorAndRepositoryForSidebarRows() {
        let actor = AttentionActor(
            login: "desktop-merge-queue[bot]",
            avatarURL: nil,
            isBot: true
        )

        let subtitle = AttentionViewerPresentationPolicy.listContextSubtitle(
            subtitle: "desktop-merge-queue[bot] · acme/pinata · Review requested",
            actor: actor,
            repository: "acme/pinata",
            viewerLogin: nil,
            hidesRepository: true
        )

        XCTAssertEqual(subtitle, "Review requested")
    }

    func testListContextSubtitleStripsRawBotPrefixAndKeepsRepositoryForMenubarRows() {
        let actor = AttentionActor(
            login: "desktop-merge-queue[bot]",
            avatarURL: nil,
            isBot: true
        )

        let subtitle = AttentionViewerPresentationPolicy.listContextSubtitle(
            subtitle: "desktop-merge-queue[bot] · acme/pinata · Review requested",
            actor: actor,
            repository: "acme/pinata",
            viewerLogin: nil,
            hidesRepository: false
        )

        XCTAssertEqual(subtitle, "acme/pinata · Review requested")
    }

    func testListContextSubtitleReturnsNilWhenActorAndRepositoryAreOnlyContext() {
        let actor = AttentionActor(login: "alberto", avatarURL: nil)

        let subtitle = AttentionViewerPresentationPolicy.listContextSubtitle(
            subtitle: "alberto · acme/pinata",
            actor: actor,
            repository: "acme/pinata",
            viewerLogin: nil,
            hidesRepository: true
        )

        XCTAssertNil(subtitle)
    }

    func testListContextSubtitleStripsPersonalizedViewerActorPrefix() {
        let actor = AttentionActor(login: "alberto", avatarURL: nil)

        let subtitle = AttentionViewerPresentationPolicy.listContextSubtitle(
            subtitle: "alberto · acme/pinata · Review approved",
            actor: actor,
            repository: "acme/pinata",
            viewerLogin: "alberto",
            hidesRepository: false
        )

        XCTAssertEqual(subtitle, "acme/pinata · Review approved")
    }
}
