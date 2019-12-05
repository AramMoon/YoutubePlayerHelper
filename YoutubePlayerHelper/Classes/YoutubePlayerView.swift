//
//  YoutubePlayerView.swift
//
//
//  Created by Aram Moon on 2019/12/05.
//  https://github.com/hmhv/YoutubePlayer-in-WKWebView

import Foundation
import WebKit
import UIKit

//* These enums represent the state of the current video in the player.
@objc public enum WKYTPlayerState : Int {
    case Unstarted = -1
    case Ended = 0
    case Playing = 1
    case Paused = 2
    case Buffering = 3
    case Queued = 5
    case Unknown = 999
}

//* These enums represent the resolution of the currently loaded video.
@objc public enum WKYTPlaybackQuality: Int {
    case Small = 0
    case Medium = 1
    case Large = 2
    case HD720 = 3
    case HD1080 = 4
    case HighRes = 5
    case Auto = 7
    case Default = 8
    case Unknown = 9
    
    func getString() -> String {
        let stArray = ["small", "medium", "large", "hd720", "hd1080", "highres","auto", "default", "unknown"]
        if self.rawValue > stArray.count {
            return "unknown"
        }else {
            return stArray[self.rawValue]
        }
    }
}

//* These enums represent error codes thrown by the player.
@objc public enum WKYTPlayerError : Int {
    case InvalidParam = 2
    case HTML5Error = 5
    case VideoNotFound = 100
    case NotEmbeddable = 101
    case CannotFindVideo = 105
    case SameAsNotEmbeddable = 150
    case Unknown = 999
}

public enum PlayerError : Error {
    case InvalidParam
    case HTML5Error
    case VideoNotFound
    case NotEmbeddable
    case CannotFindVideo
    case SameAsNotEmbeddable
    case Unknown
    case TODO
}

public protocol WKYTPlayerViewDelegate {
    
    func playerViewDidBecomeReady(_ playerView: YoutubePlayerView)
    
    func playerView(_ playerView: YoutubePlayerView, didChangeTo state: WKYTPlayerState)
    
    func playerView(_ playerView: YoutubePlayerView, didChangeTo quality: WKYTPlaybackQuality)
    
    func playerView(_ playerView: YoutubePlayerView, receivedError error: WKYTPlayerError)
    
    func playerView(_ playerView: YoutubePlayerView, didPlayTime playTime: Float)
    
    func playerViewPreferredWebViewBackgroundColor(_ playerView: YoutubePlayerView) -> UIColor
    
    func playerViewPreferredInitialLoading(_ playerView: YoutubePlayerView) -> UIView?
}

public class YoutubePlayerView: UIView {
    
    // Constants representing player callbacks.
    private var kWKYTPlayerCallbackOnReady = "onReady"
    private var kWKYTPlayerCallbackOnStateChange = "onStateChange"
    private var kWKYTPlayerCallbackOnPlaybackQualityChange = "onPlaybackQualityChange"
    private var kWKYTPlayerCallbackOnError = "onError"
    private var kWKYTPlayerCallbackOnPlayTime = "onPlayTime"
    
    private var kWKYTPlayerCallbackOnYouTubeIframeAPIReady = "onYouTubeIframeAPIReady"
    private var kWKYTPlayerCallbackOnYouTubeIframeAPIFailedToLoad = "onYouTubeIframeAPIFailedToLoad"
    
    private var kWKYTPlayerEmbedUrlRegexPattern = "^http(s)://(www.)youtube.com/embed/(.*)$"
    private var kWKYTPlayerAdUrlRegexPattern = "^http(s)://pubads.g.doubleclick.net/pagead/conversion/"
    private var kWKYTPlayerOAuthRegexPattern = "^http(s)://accounts.google.com/o/oauth2/(.*)$"
    private var kWKYTPlayerStaticProxyRegexPattern = "^https://content.googleapis.com/static/proxy.html(.*)$"
    private var kWKYTPlayerSyndicationRegexPattern = "^https://tpc.googlesyndication.com/sodar/(.*).html$"
    private var originURL: URL?
    private weak var initialLoadingView: UIView?
    
    var webView: WKWebView?
    
    var delegate: WKYTPlayerViewDelegate?
    
    public func load(withVideoId videoId: String?) -> Bool {
        return load(withVideoId: videoId, playerVars: nil)
    }
    
    public func load(withPlaylistId playlistId: String?) -> Bool {
        return load(withPlaylistId: playlistId, playerVars: nil)
    }
    
    public func load(withVideoId videoId: String?, playerVars: [AnyHashable : Any]?) -> Bool {
        var playerVars = playerVars
        if playerVars == nil {
            playerVars = [:]
        }
        var playerParams: [AnyHashable : Any]? = nil
        if let aVars = playerVars {
            playerParams = ["videoId": videoId ?? "0", "playerVars": aVars]
        }
        return load(withPlayerParams: playerParams)
    }
    
    public func load(withPlaylistId playlistId: String?, playerVars: [AnyHashable : Any]?) -> Bool {
        // Mutable copy because we may have been passed an immutable config dictionary.
        var tempPlayerVars: [AnyHashable : Any] = [:]
        tempPlayerVars["listType"] = "playlist"
        tempPlayerVars["list"] = playlistId
        if playerVars != nil {
            for (k, v) in playerVars! { tempPlayerVars[k] = v }
        }
        let playerParams = ["playerVars": tempPlayerVars]
        return load(withPlayerParams: playerParams)
    }
    // MARK: - My methods
    public func setContentsSize() {
        if let v = webView {
            if !v.scrollView.contentSize.equalTo(self.frame.size) {
                print("content Set: ", self.frame.size)
                let size = self.frame.size
                let w = size.width
                let h = size.height
                self.frame.size = CGSize(width: w+1, height: h)
            }
        }
    }
    
    // MARK: - Player methods
    public func playVideo() {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.playVideo();", completionHandler: nil)
    }
    
    public func pauseVideo() {
        notifyDelegateOfYouTubeCallbackUrl(URL(string: "ytplayer://onStateChange?data=\(WKYTPlayerState.Paused.rawValue)"))
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.pauseVideo();", completionHandler: nil)
    }
    
    public func stopVideo() {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.stopVideo();", completionHandler: nil)
    }
    
    public func seek(toSeconds seekToSeconds: Float, allowSeekAhead: Bool) {
        let secondsValue = seekToSeconds
        let allowSeekAheadValue = allowSeekAhead.description
        let command = "player.seekTo(\(secondsValue), \(allowSeekAheadValue));"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    
    // MARK: - Cueing methods
    public func cueVideo(byId videoId: String?, startSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let startSecondsValue = startSeconds
        let qualityValue = suggestedQuality.rawValue
        let command = "player.cueVideoById('\(videoId ?? "")', \(startSecondsValue), '\(qualityValue)');"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    
    public func cueVideo(byId videoId: String?, startSeconds: Float, endSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let startSecondsValue = startSeconds
        let endSecondsValue = endSeconds
        let qualityValue = suggestedQuality.rawValue
        let command = "player.cueVideoById({'videoId': '\(videoId ?? "")', 'startSeconds': \(startSecondsValue), 'endSeconds': \(endSecondsValue), 'suggestedQuality': '\(qualityValue)'});"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    
    public func loadVideo(byId videoId: String?, startSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let startSecondsValue = startSeconds
        let qualityValue = suggestedQuality.rawValue
        let command = "player.loadVideoById('\(videoId ?? "")', \(startSecondsValue), '\(qualityValue)');"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    public func loadVideo(byId videoId: String?, startSeconds: Float, endSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let startSecondsValue = startSeconds
        let endSecondsValue = endSeconds
        let qualityValue = suggestedQuality.rawValue
        let command = "player.loadVideoById({'videoId': '\(videoId ?? "")', 'startSeconds': \(startSecondsValue), 'endSeconds': \(endSecondsValue), 'suggestedQuality': '\(qualityValue )'});"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    public func cueVideo(byURL videoURL: String?, startSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let startSecondsValue = startSeconds
        let qualityValue = suggestedQuality.rawValue
        let command = "player.cueVideoByUrl('\(videoURL ?? "")', \(startSecondsValue), '\(qualityValue )');"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    public func cueVideo(byURL videoURL: String?, startSeconds: Float, endSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let startSecondsValue = startSeconds
        let endSecondsValue = endSeconds
        let qualityValue = suggestedQuality.rawValue
        let command = "player.cueVideoByUrl('\(videoURL ?? "")', \(startSecondsValue), \(endSecondsValue), '\(qualityValue )');"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    public func loadVideo(byURL videoURL: String?, startSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let startSecondsValue = startSeconds
        let qualityValue = suggestedQuality.rawValue
        let command = "player.loadVideoByUrl('\(videoURL ?? "")', \(startSecondsValue), '\(qualityValue )');"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    public func loadVideo(byURL videoURL: String?, startSeconds: Float, endSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let startSecondsValue = startSeconds
        let endSecondsValue = endSeconds
        let qualityValue = suggestedQuality.rawValue
        let command = "player.loadVideoByUrl('\(videoURL ?? "")', \(startSecondsValue), \(endSecondsValue), '\(qualityValue )');"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    // MARK: - Cueing methods for lists
    public func cuePlaylist(byPlaylistId playlistId: String?, index: Int, startSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let playlistIdString = "'\(playlistId ?? "")'"
        cuePlaylist(playlistIdString, index: index, startSeconds: startSeconds, suggestedQuality: suggestedQuality)
    }
    
    public func cuePlaylist(byVideos videoIds: [String], index: Int, startSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        cuePlaylist(videoIds.joined(separator: ","), index: index, startSeconds: startSeconds, suggestedQuality: suggestedQuality)
    }
    
    public func loadPlaylist(byPlaylistId playlistId: String, index: Int, startSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        loadPlaylist(playlistId, index: index, startSeconds: startSeconds, suggestedQuality: suggestedQuality)
    }
    
    public func loadPlaylist(byVideos videoIds: [String], index: Int, startSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        loadPlaylist(videoIds.joined(separator: ","), index: index, startSeconds: startSeconds, suggestedQuality: suggestedQuality)
    }

    // MARK: - Setting the playback rate
    public func getPlaybackRate(_ completionHandler: ((_ playbackRate: Float, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getPlaybackRate();", completionHandler: { response, error in
            if completionHandler != nil {
                if error != nil {
                    completionHandler?(0, error)
                } else {
                    if let pb = response as? Float {
                        completionHandler?(pb, nil)
                        
                    }else {
                        completionHandler?(0, nil)
                    }
                }
            }
        })
    }
    
    public func setPlaybackRate(_ suggestedRate: Float) {
        let command = "player.setPlaybackRate(\(suggestedRate));"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    
    public func getAvailablePlaybackRates(_ completionHandler: ((_ availablePlaybackRates: [Any]?, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getAvailablePlaybackRates();", completionHandler: { (response, error) in
            if completionHandler != nil {
                if error != nil {
                    completionHandler?(nil, error)
                } else {
                    completionHandler?(nil, PlayerError.TODO)

                }
                
            }
        })
    }
    
    // MARK: - Setting playback behavior for playlists
    public func setLoop(_ loop: Bool) {
        let loopPlayListValue = loop.description
        let command = "player.setLoop(\(loopPlayListValue ));"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    
    public func setShuffle(_ shuffle: Bool) {
        let shufflePlayListValue = shuffle.description
        let command = "player.setShuffle(\(shufflePlayListValue));"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    
    // MARK: - Playback status
    public func getVideoLoadedFraction(_ completionHandler: ((_ videoLoadedFraction: Float, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getVideoLoadedFraction();", completionHandler: { response, error in
            if completionHandler != nil {
                if error != nil {
                    completionHandler?(0, error)
                } else {
                    if let fraction = response as? Float {
                        completionHandler?(fraction, nil)
                        
                    }else {
                        completionHandler?(0, nil)
                    }
                }
            }
        })
    }
    
    public func getPlayerState(_ completionHandler: ((_ playerState: WKYTPlayerState, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getPlayerState();", completionHandler: { (response, error) in
            if error != nil {
                completionHandler?(.Unknown, error)
            } else  {
                if let res = response as? Int {
                    completionHandler?(WKYTPlayerState(rawValue: res) ?? .Unknown, nil)
                } else {
                    completionHandler?(.Unknown, nil)
                }
            }
        })
    }
    
    public func getCurrentTime(_ completionHandler: ((_ currentTime: Float, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getCurrentTime();", completionHandler: { response, error in
            if completionHandler != nil {
                if error != nil {
                    completionHandler?(0, error)
                } else {
                    if let time = response as? Float {
                        completionHandler?(time, nil)
                    }else{
                        completionHandler?(0, nil)
                    }
                }
            }
        })
    }
    
    // Playback quality
    public func getPlaybackQuality(_ completionHandler: ((_ playbackQuality: WKYTPlaybackQuality, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getPlaybackQuality();", completionHandler: { response, error in
            if completionHandler != nil {
                if error != nil {
                    completionHandler?(.Unknown, error)
                } else {
                    if let res = response as? Int {
                        completionHandler?(WKYTPlaybackQuality(rawValue: res) ?? .Unknown, nil)
                    }else{
                        completionHandler?( .Unknown, nil)
                    }
                }
            }
        })
    }
    
    public func setPlaybackQuality(_ suggestedQuality: WKYTPlaybackQuality) {
        let qualityValue = suggestedQuality.rawValue
        let command = "player.setPlaybackQuality('\(qualityValue)');"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    
    // MARK: - Video information methods
    public func getDuration(_ completionHandler: ((_ duration: TimeInterval, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getDuration();", completionHandler: { response, error in
            if completionHandler != nil {
                if error != nil {
                    completionHandler?(0, error)
                } else {
                    if let duration = response as? Double{
                        completionHandler?(duration, nil)
                    } else {
                        completionHandler?(0, nil)
                    }
                }
            }
        })
    }
    
    public func getVideoUrl(_ completionHandler: ((_ videoUrl: URL?, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getVideoUrl();", completionHandler: { response, error in
            if error != nil {
                completionHandler?(nil, error)
            } else {
                if let res = response as? String {
                    completionHandler?(URL(string: res), nil)
                }else {
                    completionHandler?(nil, PlayerError.InvalidParam)
                }
            }
        })
    }
    
    public func getVideoEmbedCode(_ completionHandler: ((_ videoEmbedCode: String?, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getVideoEmbedCode();", completionHandler: { response, error in
            if completionHandler != nil {
                if error != nil {
                    completionHandler?(nil, error)
                } else {
                    if let res = response as? String {
                        completionHandler?(res, nil)
                    }else{
                        completionHandler?(nil, PlayerError.NotEmbeddable)
                    }
                }
            }
        })
    }
    
    // MARK: - Playlist methods
    public func getPlaylist(_ completionHandler: ((_ playlist: [String]?, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getPlaylist();", completionHandler: { (response, error) in
            if completionHandler != nil {
                if error != nil {
                    completionHandler?(nil, error)
                } else {
                    if let res = response as? [String] {
                        completionHandler?(res, nil)
                    }else {
                        completionHandler?(nil, PlayerError.TODO)
                    }
                }
            }
        })
    }
    
    public func getPlaylistIndex(_ completionHandler: ((_ playlistIndex: Int, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getPlaylistIndex();", completionHandler: { (response, error) in
            if error != nil {
                completionHandler?(0, error)
            } else {
                if let res = response as? Int {
                    completionHandler?(res, nil)
                }else{
                    completionHandler?(0, PlayerError.CannotFindVideo)
                }
            }
        })
    }
    
    // MARK: - Playing a video in a playlist
    public func nextVideo() {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.nextVideo();", completionHandler: nil)
    }
    
    public func previousVideo() {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.previousVideo();", completionHandler: nil)
    }
    
    public func playVideo(at index: Int) {
        let command = "player.playVideoAt(\(Int32(index)));"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    
    // MARK: - Changing the player volume
    /**
     * Mutes the player. Corresponds to this method from
     * the JavaScript API:
     *   https://developers.google.com/youtube/iframe_api_reference#mute
     */
    public func mute() {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.mute();", completionHandler: nil)
    }
    
    public func unMute() {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.unMute();", completionHandler: nil)
    }
    
    public func isMuted(_ completionHandler: ((_ isMuted: Bool, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.isMuted();", completionHandler: { response, error in
            if error != nil {
                completionHandler?(false, error)
            } else {
                if let res = response as? Bool {
                    completionHandler?(res, nil)
                    
                }else {
                    completionHandler?(false, PlayerError.Unknown)
                }
            }
        })
    }
    
    // MARK: - Helper methods
    public func getAvailableQualityLevels(_ completionHandler: ((_ availableQualityLevels: [WKYTPlaybackQuality]?, _ error: Error?) -> Void)? = nil) {
        evaluatingJavaScript(fromEvaluatingJavaScript: "player.getAvailableQualityLevels().toString();", completionHandler: { response, error in
            if completionHandler != nil {
                if error != nil {
                    completionHandler?(nil, error)
                } else {
                    if let res = response as? String {
                        let rawQualityValues = res.components(separatedBy: ",")
                        var levels: [WKYTPlaybackQuality] = []
                        for rawQualityValue in rawQualityValues {
                            let quality: WKYTPlaybackQuality = WKYTPlaybackQuality(rawValue: Int(rawQualityValue) ?? 999) ?? .Auto
                            levels.append(quality)
                        }
                        completionHandler?(levels, nil)
                    } else {
                        completionHandler?(nil, PlayerError.InvalidParam)
                    }
                    
                }
            }
        })
    }
    
    // MARK: - Private methods
    /**
     * Private method to handle "navigation" to a callback URL of the format
     * ytplayer://action?data=someData
     * This is how the UIWebView communicates with the containing Objective-C code.
     * Side effects of this method are that it calls methods on this class's delegate.
     *
     * @param url A URL of the format ytplayer://action?data=value.
     */
    public func notifyDelegateOfYouTubeCallbackUrl(_ url: URL?) {
        let action: String = url?.host ?? ""
        // We know the query can only be of the format ytplayer://action?data=SOMEVALUE,
        // so we parse out the value.
        let query = url?.query
        var data: String = ""
        if query != nil {
            data = query?.components(separatedBy: "=")[1] ?? ""
        }
        
        if action.isEqual(kWKYTPlayerCallbackOnReady) {
            if (initialLoadingView != nil) {
                initialLoadingView?.removeFromSuperview()
            }
            delegate?.playerViewDidBecomeReady(self)
        }else if action.isEqual(kWKYTPlayerCallbackOnStateChange) {
            if let stateInt = Int(data) {
                delegate?.playerView(self, didChangeTo: WKYTPlayerState(rawValue: stateInt) ?? .Unknown)
            } else {
                delegate?.playerView(self, didChangeTo: WKYTPlayerState.Unknown)
            }
        }else if action.isEqual(kWKYTPlayerCallbackOnPlaybackQualityChange) {
            let quality: WKYTPlaybackQuality = WKYTPlaybackQuality(rawValue: Int(data) ?? 999) ?? .Auto
            delegate?.playerView(self, didChangeTo: quality)
        }else if action.isEqual(kWKYTPlayerCallbackOnError) {
            let error: WKYTPlayerError = WKYTPlayerError(rawValue: Int(data) ?? 999) ?? .Unknown
            delegate?.playerView(self, receivedError: error)
        }else if (action == kWKYTPlayerCallbackOnPlayTime) {
            let time = Float(data) ?? 0.0
            delegate?.playerView(self, didPlayTime: time)
        }else if (action == kWKYTPlayerCallbackOnYouTubeIframeAPIFailedToLoad) {
            if (initialLoadingView != nil) {
                initialLoadingView?.removeFromSuperview()
            }
        }
    }
    
    public func handleHttpNavigation(to url: URL?) -> Bool {
        
        let ytRegex = try? NSRegularExpression(pattern: kWKYTPlayerEmbedUrlRegexPattern, options: .caseInsensitive)
        let ytMatch: NSTextCheckingResult? = ytRegex?.firstMatch(in: url?.absoluteString ?? "", options: [], range: NSRange(location: 0, length: url?.absoluteString.count ?? 0))
        let adRegex = try? NSRegularExpression(pattern: kWKYTPlayerAdUrlRegexPattern, options: .caseInsensitive)
        let adMatch: NSTextCheckingResult? = adRegex?.firstMatch(in: url?.absoluteString ?? "", options: [], range: NSRange(location: 0, length: url?.absoluteString.count ?? 0))
        let syndicationRegex = try? NSRegularExpression(pattern: kWKYTPlayerSyndicationRegexPattern, options: .caseInsensitive)
        let syndicationMatch: NSTextCheckingResult? = syndicationRegex?.firstMatch(in: url?.absoluteString ?? "", options: [], range: NSRange(location: 0, length: url?.absoluteString.count ?? 0))
        let oauthRegex = try? NSRegularExpression(pattern: kWKYTPlayerOAuthRegexPattern, options: .caseInsensitive)
        let oauthMatch: NSTextCheckingResult? = oauthRegex?.firstMatch(in: url?.absoluteString ?? "", options: [], range: NSRange(location: 0, length: url?.absoluteString.count ?? 0))
        let staticProxyRegex = try? NSRegularExpression(pattern: kWKYTPlayerStaticProxyRegexPattern, options: .caseInsensitive)
        let staticProxyMatch: NSTextCheckingResult? = staticProxyRegex?.firstMatch(in: url?.absoluteString ?? "", options: [], range: NSRange(location: 0, length: url?.absoluteString.count ?? 0))
        if ytMatch != nil || adMatch != nil || oauthMatch != nil || staticProxyMatch != nil || syndicationMatch != nil {
            return true
        } else {
            if let anUrl = url {
                UIApplication.shared.open(anUrl, options: [:], completionHandler: nil)
            }
            return false
        }
    }
    
    /**
     * Private helper method to load an iframe player with the given player parameters.
     *
     * @param additionalPlayerParams An NSDictionary of parameters in addition to required parameters
     *                               to instantiate the HTML5 player with. This differs depending on
     *                               whether a single video or playlist is being loaded.
     * @return YES if successful, NO if not.
     */
    public func load(withPlayerParams additionalPlayerParams: [AnyHashable : Any]?) -> Bool {
        let playerCallbacks = ["onReady": "onReady", "onStateChange": "onStateChange", "onPlaybackQualityChange": "onPlaybackQualityChange", "onError": "onPlayerError"]
        var playerParams: [AnyHashable : Any] = [:]
        if additionalPlayerParams != nil {
            for (k, v) in additionalPlayerParams! { playerParams[k] = v }
        }
        if playerParams["height"] == nil {
            playerParams["height"] = "100%"
        }
        if playerParams["width"] == nil {
            playerParams["width"] = "100%"
        }
        playerParams["events"] = playerCallbacks
        if playerParams["playerVars"] != nil {
            var playerVars: [AnyHashable : Any] = [:]
            for (k, v) in playerParams["playerVars"] as? [String: String] ?? [:]{
                playerVars[k] = v
            }
            if playerVars["origin"] == nil {
                originURL = URL(string: "about:blank")
            } else {
                originURL = URL(string: playerVars["origin"] as? String ?? "")
            }
        } else {
            // This must not be empty so we can render a '{}' in the output JSON
            playerParams["playerVars"] = [AnyHashable : Any]()
        }
        // Remove the existing webView to reset any state
        webView?.removeFromSuperview()
        if let aView = createNewWebView() {
            webView = aView
        }
        addSubview(webView!)
        webView?.translatesAutoresizingMaskIntoConstraints = false
        webView?.frame = CGRect(origin: CGPoint.zero, size: self.frame.size)
        guard let bundle = Bundle(identifier: "org.cocoapods.YoutubePlayerHelper") else {
            print("Bundle is nil")
            return false
        }
        guard let fileData = NSDataAsset(name: "iframeHtml", bundle: bundle)?.data else {
            print("iframe HTML file is nil")
            return false
        }
        
        let embedHTMLTemplate = String.init(data: fileData, encoding: .utf8)!
        
        // Render the playerVars as a JSON dictionary.
        let jsonData: Data? = try? JSONSerialization.data(withJSONObject: playerParams, options: .prettyPrinted)
        
        var playerVarsJsonString: String? = nil
        if let aData = jsonData {
            playerVarsJsonString = String(data: aData, encoding: .utf8)
        }
        let embedHTML = String(format: embedHTMLTemplate , playerVarsJsonString ?? "")
        webView?.loadHTMLString(embedHTML, baseURL: originURL)
        webView?.navigationDelegate = self
        let initialLoadingView: UIView? = delegate?.playerViewPreferredInitialLoading(self)
        if initialLoadingView != nil {
            initialLoadingView?.frame = bounds
            initialLoadingView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            if let aView = initialLoadingView {
                addSubview(aView)
            }
            self.initialLoadingView = initialLoadingView
        }
        
        return true
    }
    
    /**
     * Private method for cueing both cases of playlist ID and array of video IDs. Cueing
     * a playlist does not start playback.
     *
     * @param cueingString A JavaScript string representing an array, playlist ID or list of
     *                     video IDs to play with the playlist player.
     * @param index 0-index position of video to start playback on.
     * @param startSeconds Seconds after start of video to begin playback.
     * @param suggestedQuality Suggested WKYTPlaybackQuality to play the videos.
     */
    public func cuePlaylist(_ cueingString: String?, index: Int, startSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let indexValue = Int32(index)
        let startSecondsValue = startSeconds
        let qualityValue = suggestedQuality.rawValue
        let command = "player.cuePlaylist(\(cueingString ?? ""), \(indexValue), \(startSecondsValue), '\(qualityValue)');"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    
    /**
     * Private method for loading both cases of playlist ID and array of video IDs. Loading
     * a playlist automatically starts playback.
     *
     * @param cueingString A JavaScript string representing an array, playlist ID or list of
     *                     video IDs to play with the playlist player.
     * @param index 0-index position of video to start playback on.
     * @param startSeconds Seconds after start of video to begin playback.
     * @param suggestedQuality Suggested WKYTPlaybackQuality to play the videos.
     */
    public func loadPlaylist(_ cueingString: String?, index: Int, startSeconds: Float, suggestedQuality: WKYTPlaybackQuality) {
        let indexValue = Int32(index)
        let startSecondsValue = startSeconds
        let qualityValue = suggestedQuality.rawValue
        let command = "player.loadPlaylist(\(cueingString ?? ""), \(indexValue), \(startSecondsValue), '\(qualityValue)');"
        evaluatingJavaScript(fromEvaluatingJavaScript: command, completionHandler: nil)
    }
    
    /**
     * Private method for evaluating JavaScript in the WebView.
     *
     * @param jsToExecute The JavaScript code in string format that we want to execute.
     */
    public func evaluatingJavaScript(fromEvaluatingJavaScript jsToExecute: String?, completionHandler: ((_ response: Any?, _ error: Error?) -> ())? ) {
        webView?.evaluateJavaScript(jsToExecute ?? "", completionHandler: { (response, error) in
            completionHandler?(response, error)
        })
        
    }
    
    // MARK: - Exposed for Testing
    public func createNewWebView() -> WKWebView? {
        // WKWebView equivalent for UIWebView's scalesPageToFit
        // http://stackoverflow.com/questions/26295277/wkwebview-equivalent-for-uiwebviews-scalespagetofit
        let jScript = "var meta = document.createElement('meta'); meta.setAttribute('name', 'viewport'); meta.setAttribute('content', 'width=device-width'); document.getElementsByTagName('head')[0].appendChild(meta);"
        let wkUScript = WKUserScript.init(source: jScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let wkUController = WKUserContentController.init()
        wkUController.addUserScript(wkUScript)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = wkUController
        configuration.allowsInlineMediaPlayback = true
        //        configuration.mediaPlaybackRequiresUserAction = false
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: bounds, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        if webView.backgroundColor == UIColor.clear {
            webView.isOpaque = false
        }
        return webView
    }
    
    public func removeWebView() {
        webView?.removeFromSuperview()
        webView = nil
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        webView?.frame.size = self.frame.size
    }
}

extension YoutubePlayerView: WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("userContentController",userContentController, message)
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let request: URLRequest = navigationAction.request
        if request.url?.host?.isEqual(originURL?.host) ?? false {
            decisionHandler(.allow)
            return
        } else if request.url?.scheme?.isEqual("ytplayer") ?? false {
            notifyDelegateOfYouTubeCallbackUrl(request.url)
            decisionHandler(.cancel)
            return
        } else if request.url?.scheme?.isEqual("http") ?? false || request.url?.scheme?.isEqual("https") ?? false {
            if handleHttpNavigation(to: request.url) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
            return
        }
        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (initialLoadingView != nil) {
            initialLoadingView?.removeFromSuperview()
        }
    }
    
}
