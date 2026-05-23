import SwiftUI

// MARK: - Public Signals Card

/// Shows recent LinkedIn posts, news mentions, and Twitter/X activity for a contact.
/// Displayed in ContactDetailView below the enrichment/synthesis cards.
struct PublicSignalsCard: View {

    @Binding var signals:      ContactSignals?
    @Binding var isLoading:    Bool
    let onRefresh: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(6)
                    .background(Color.revboOrange)
                    .clipShape(Circle())

                Text("PUBLIC SIGNALS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.revboOrange)
                    .tracking(1.2)

                Spacer()

                // Refresh button
                Button(action: onRefresh) {
                    HStack(spacing: 4) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(Color.revboOrange)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        Text("Refresh")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.revboOrange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.revboOrange.opacity(0.12))
                    .clipShape(Capsule())
                }
                .disabled(isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().background(Color.revboOrange.opacity(0.25))

            // ── Body ──────────────────────────────────────────────────────
            if isLoading && signals == nil {
                // Initial loading state
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Color.revboOrange)
                        .padding(.vertical, 24)
                    Spacer()
                }
            } else if let signals, !signals.isEmpty {
                VStack(alignment: .leading, spacing: 0) {

                    // ── LinkedIn Posts ────────────────────────────────────
                    if !signals.linkedin_posts.isEmpty {
                        SignalSectionHeader(
                            icon: "briefcase.fill",
                            title: "LinkedIn",
                            count: signals.linkedin_posts.count
                        )
                        ForEach(Array(signals.linkedin_posts.prefix(3).enumerated()), id: \.offset) { index, post in
                            SignalPostRow(
                                text: post.text,
                                subtitle: post.date,
                                url: post.url,
                                metric: post.likes > 0 ? "\(post.likes) likes" : nil
                            )
                            if index < min(2, signals.linkedin_posts.count - 1) {
                                Divider()
                                    .background(Color.white.opacity(0.05))
                                    .padding(.leading, 16)
                            }
                        }
                    }

                    // ── News ──────────────────────────────────────────────
                    if !signals.news.isEmpty {
                        if !signals.linkedin_posts.isEmpty {
                            Divider().background(Color.white.opacity(0.07))
                        }
                        SignalSectionHeader(
                            icon: "newspaper.fill",
                            title: "News",
                            count: signals.news.count
                        )
                        ForEach(Array(signals.news.prefix(3).enumerated()), id: \.offset) { index, item in
                            SignalPostRow(
                                text: item.title,
                                subtitle: "\(item.source) · \(item.published_at)",
                                url: item.url,
                                metric: nil
                            )
                            if index < min(2, signals.news.count - 1) {
                                Divider()
                                    .background(Color.white.opacity(0.05))
                                    .padding(.leading, 16)
                            }
                        }
                    }

                    // ── Twitter / X ───────────────────────────────────────
                    if !signals.twitter.isEmpty {
                        if !signals.linkedin_posts.isEmpty || !signals.news.isEmpty {
                            Divider().background(Color.white.opacity(0.07))
                        }
                        SignalSectionHeader(
                            icon: "at",
                            title: "X / Twitter",
                            count: signals.twitter.count
                        )
                        ForEach(Array(signals.twitter.prefix(3).enumerated()), id: \.offset) { index, tweet in
                            SignalPostRow(
                                text: tweet.text,
                                subtitle: tweet.created_at,
                                url: tweet.url,
                                metric: tweet.likes > 0 ? "\(tweet.likes) likes" : nil
                            )
                            if index < min(2, signals.twitter.count - 1) {
                                Divider()
                                    .background(Color.white.opacity(0.05))
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            } else {
                // Empty state
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text("No public signals found")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .padding(14)
            }
        }
        .background(Color.revboSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - Section Header

private struct SignalSectionHeader: View {
    let icon:  String
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.revboMuted)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.revboMuted)
            Text("(\(count))")
                .font(.caption2)
                .foregroundStyle(Color.revboSubtle)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

// MARK: - Signal Row

private struct SignalPostRow: View {
    let text:     String
    let subtitle: String
    let url:      String
    let metric:   String?

    @Environment(\.openURL) private var openURL

    private var truncatedText: String {
        text.count > 120 ? String(text.prefix(120)) + "…" : text
    }

    var body: some View {
        Button {
            if let link = URL(string: url), !url.isEmpty {
                openURL(link)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(truncatedText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.revboText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.revboSubtle)
                        if let metric {
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.revboSubtle)
                            Text(metric)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.revboMuted)
                        }
                    }
                }
                Spacer()
                if !url.isEmpty {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.revboSubtle)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}
