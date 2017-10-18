//
//  Podcast.swift
//  Doughnut
//
//  Created by Chris Dyer on 28/09/2017.
//  Copyright © 2017 Chris Dyer. All rights reserved.
//

import Foundation
import GRDB
import FeedKit

class Podcast: Record {
  var id: Int64?
  var title: String
  var path: String
  var feed: String?
  var description: String?
  var link: String?
  var author: String?
  var language: String?
  var copyright: String?
  var pubDate: Date?
  var image: NSImage?
  var imageUrl: String?
  var lastParsed: Date?
  var subscribedAt: Date
  
  var episodes = [Episode]()
  
  var loading = false
  
  override class var databaseTableName: String {
    return "podcasts"
  }
  
  init(title: String) {
    self.title = title
    self.path = Library.sanitizePath(title)
    self.subscribedAt = Date()
    
    super.init()
  }
  
  required init(row: Row) {
    id = row["id"]
    title = row["title"]
    path = row["path"]
    feed = row["feed"]
    description = row["description"]
    link = row["link"]
    author = row["author"]
    language = row["language"]
    copyright = row["copyright"]
    pubDate = row["pub_date"]
    
    let imageData: DatabaseValue = row["image"]
    if !imageData.isNull {
      image = NSImage(data: row["image"])
    }
    
    imageUrl = row["image_url"]
    lastParsed = row["last_parsed"]
    subscribedAt = row["subscribed_at"]
    
    super.init(row: row)
  }
  
  override func encode(to container: inout PersistenceContainer) {
    container["id"] = id
    container["title"] = title
    container["path"] = path
    container["feed"] = feed
    container["description"] = description
    container["link"] = link
    container["author"] = author
    container["language"] = language
    container["copyright"] = copyright
    container["pub_date"] = pubDate
    container["image"] = compressImage()
    container["image_url"] = imageUrl
    container["last_parsed"] = lastParsed
    container["subscribed_at"] = subscribedAt
  }
  
  override func didInsert(with rowID: Int64, for column: String?) {
    id = rowID
    
    for episode in episodes {
      episode.podcast = self
      episode.podcastId = self.id
    }
  }
  
  func storagePath() -> URL? {
    let pathUrl = URL(fileURLWithPath: self.path, relativeTo: Library.global.path)
    var isDir = ObjCBool(true)
    if FileManager.default.fileExists(atPath: pathUrl.path, isDirectory: &isDir) == false {
      do {
        try FileManager.default.createDirectory(at: pathUrl, withIntermediateDirectories: true, attributes: nil)
      } catch {
        print("Failed to create directory \(error)")
      }
    }
    
    return pathUrl
  }
  
  func loadEpisodes(db: Database) {
    do {
      episodes = try Episode.filter(Column("podcast_id") == self.id).fetchAll(db)
      
      for e in episodes {
        if e.podcastId == self.id {
          e.podcast = self
        }
      }
    } catch let error as DatabaseError {
      Library.handleDatabaseError(error)
    } catch {}
  }
  
  private func storeImage(_ url: URL) {
    imageUrl = url.absoluteString
    
    if let downloaded = NSImage(contentsOf: url) {
      image = Podcast.resizeArtwork(image: downloaded, w: 1024, h: 1024)
    }
  }
  
  private func compressImage() -> Data? {
    guard let image = image else { return nil }
    guard let tiffData = image.tiffRepresentation else { return nil }
    guard let imageRep = NSBitmapImageRep(data: tiffData) else { return nil }
    return imageRep.representation(using: .jpeg, properties: [:])
  }
  
  // Called within subscribe or reload
  // 1. Update feed properties
  // 2. Check for new episodes
  func parse(feed: RSSFeed) -> [Episode] {
    self.description = feed.description
    self.link = feed.link
    self.author = feed.iTunes?.iTunesAuthor
    self.language = feed.language
    self.copyright = feed.copyright
    self.pubDate = feed.pubDate
    
    if let feedUrl = URL(string: self.feed ?? "") {
      // Prioritize iTunes image url over regular RSS
      if let iTunesImageUrl = feed.iTunes?.iTunesImage?.attributes?.href {
        if let imageUrl = URL(string: iTunesImageUrl, relativeTo: feedUrl) {
          storeImage(imageUrl)
        }
      } else if let rssImageUrl = feed.image?.url {
        if let imageUrl = URL(string: rssImageUrl, relativeTo: feedUrl) {
          storeImage(imageUrl)
        }
      }
    }
    
    self.lastParsed = Date()
    
    var newEpisodes = [Episode]()
    
    for item in feed.items ?? [] {
      guard let title = item.title else { continue }
      guard let guid = item.guid?.value else { continue }
      
      if let exists = self.episodes.first(where: { (e) -> Bool in
        return e.guid == guid || e.title == title
      }) {
        // Episode already exists as `exists`
        exists.parse(feedItem: item)
      } else {
        let episode = Episode(title: title, guid: guid)
        episode.parse(feedItem: item)
        episode.podcast = self
        episode.podcastId = self.id
        
        self.episodes.append(episode)
        newEpisodes.append(episode)
      }
    }
    
    return newEpisodes
  }

  func fetch() -> [Episode] {
    guard let feed = self.feed else { return [] }
    guard let feedUrl = URL(string: feed) else { return [] }
    guard let parser = FeedParser(URL: feedUrl) else { return [] }
    
    let result = parser.parse()
    if result.isFailure && result.error != nil {
      print("Error reloading \(self.title): \(String(describing: result.error?.debugDescription))")
      return []
    } else {
      guard let rssFeed = result.rssFeed else { return [] }
      
      return self.parse(feed: rssFeed)
    }
  }
  
  static func subscribe(feedUrl: URL) -> Podcast? {
    guard let parser = FeedParser(URL: feedUrl) else { return nil }
      
    let result = parser.parse()
    if result.isFailure && result.error != nil {
      NSApplication.shared.presentError(result.error!)
      return nil
    } else {
      guard let rssFeed = result.rssFeed else { return nil }
      guard let title = rssFeed.title else { return nil }
      
      let podcast = Podcast(title: title)
      podcast.feed = feedUrl.absoluteString
      let _ = podcast.parse(feed: rssFeed)
      
      return podcast
    }
  }
  
  // Detect either an iTunes podcast or RSS feed and call completion with resulting podcast
  static func detect(url: String, completion: @escaping (_ result: Podcast?) -> Void) {
    DispatchQueue.global(qos: .background).async {
      if url.contains("itunes.apple.com") {
        Utils.iTunesFeedUrl(iTunesUrl: url, completion: { (feedUrl) in
          guard let feedUrl = URL(string: feedUrl ?? "") else {
            DispatchQueue.main.async {
              completion(nil)
            }
            return
          }
          
          DispatchQueue.main.async {
            completion(Podcast.subscribe(feedUrl: feedUrl))
          }
        })
      } else {
        guard let url = URL(string: url) else {
          DispatchQueue.main.async {
            completion(nil)
          }
          return
        }
        
        DispatchQueue.main.async {
          completion(Podcast.subscribe(feedUrl: url))
        }
      }
    }
  }
  
  static func resizeArtwork(image: NSImage, w: Int, h: Int) -> NSImage {
    let destSize = NSMakeSize(CGFloat(w), CGFloat(h))
    let newImage = NSImage(size: destSize)
    newImage.lockFocus()
    image.draw(in: NSMakeRect(0, 0, destSize.width, destSize.height), from: NSMakeRect(0, 0, image.size.width, image.size.height), operation: NSCompositingOperation.sourceOver, fraction: CGFloat(1))
    newImage.unlockFocus()
    newImage.size = destSize
    return NSImage(data: newImage.tiffRepresentation!)!
  }
}