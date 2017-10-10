//
//  Library.swift
//  Doughnut
//
//  Created by Chris Dyer on 27/09/2017.
//  Copyright © 2017 Chris Dyer. All rights reserved.
//

import Foundation
import FeedKit
import GRDB

class Library: NSObject {
  static var global = Library()
  static let databaseFilename = "Doughnut Library.dnl"
  
  enum Events:String {
    case Subscribed = "Subscribed"
    case Unsubscribed = "Unsubscribed"
    case Loaded = "Loaded"
    case Reloaded = "Reloaded"
    case PodcastUpdated = "PodcastUpdated"
    
    var notification: Notification.Name {
      return Notification.Name(rawValue: self.rawValue)
    }
  }
  
  let path: URL
  var dbQueue: DatabaseQueue?
  
  var podcasts = [Podcast]()
  
  var downloads = [Download]()
  
  override init() {
    // Look for libaryPath stoed as in prefs
    if let prefPath = Preference.libraryPath() {
      var isDir = ObjCBool(true)
      if FileManager.default.fileExists(atPath: prefPath.path, isDirectory: &isDir) {
        self.path = prefPath
      } else {
        // A previous library was created that we can't access, prompt the user
        if let path = Library.locate() {
          self.path = path
        } else {
          fatalError("No library located!")
        }
      }
    } else {
      self.path = Preference.defaultLibraryPath()
    }
  }
  
  func connect() -> Bool {
    do {
      dbQueue = try DatabaseQueue(path: databaseFile().path)
      
      if let dbQueue = dbQueue {
        try LibraryMigrations.migrate(db: dbQueue)
        print("Connected to Doughnut library at \(path.path)")
        
        try dbQueue.inDatabase({ db in
          podcasts = try Podcast.fetchAll(db)
          
          for podcast in podcasts {
            podcast.fetchEpisodes(db: db)
            
            #if DEBUG
            print("Loading \(podcast.title) with \(podcast.episodes.count) episodes")
            #endif
          }
          
          NotificationCenter.default.post(name: Events.Loaded.notification, object: nil)
        })
        
        return true
      } else {
        return false
      }
    } catch {
      print("Failed to connect to \(databaseFile().path)")
      return false
    }
  }
  
  func databaseFile() -> URL {
    return self.path.appendingPathComponent(Library.databaseFilename)
  }
  
  static private func databaseFile(inPath: URL) -> URL {
    return inPath.appendingPathComponent(Library.databaseFilename)
  }
  
  static private func locate() -> URL? {
    let alert = NSAlert()
    alert.addButton(withTitle: "Locate Library")
    alert.addButton(withTitle: "New Library")
    alert.addButton(withTitle: "Quit")
    alert.messageText = "Doughnut Library Not Found"
    alert.informativeText = "Your Doughnut library could not be found. If you have an existing library, choose to locate it or create a blank new podcast library."
    
    let result = alert.runModal()
    if result == .alertFirstButtonReturn {
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      
      panel.runModal()
      return panel.url
    } else if result == .alertSecondButtonReturn {
      return Preference.defaultLibraryPath()
    } else {
      return nil
    }
  }
  
  static func handleDatabaseError(_ error: Error) {
    let alert = NSAlert()
    
  }
  
  //
  // General library methods
  
  func detectedNewEpisodes(podcast: Podcast, episodes: [Episode]) {
    
  }
  
  func subscribe(url: String) -> Podcast? {
    guard let dbQueue = self.dbQueue else { return nil }
    guard let feedUrl = URL(string: url) else { return nil }
    
    // Check if the podcast is already subscribed to
    do {
      let existing = try dbQueue.inDatabase({ db -> Podcast? in
        return try Podcast.filter(Column("feed") == feedUrl.absoluteString).fetchOne(db)
      })
      
      if existing != nil {
        return nil
      }
    } catch {
      Library.handleDatabaseError(error)
      return nil
    }
    
    if let podcast = Podcast.subscribe(feedUrl: feedUrl) {
      if podcast.invokeSave(dbQueue: dbQueue) && podcast.saveEpisodes(dbQueue: dbQueue) {
        self.podcasts.append(podcast)
        NotificationCenter.default.post(name: Events.Subscribed.notification, object: nil)
        self.detectedNewEpisodes(podcast: podcast, episodes: podcast.episodes)
        
        return podcast
      }
    }
    
    return nil
  }
  
  func unsubscribe(podcast: Podcast) {
    
  }
  
  func podcast(id: Int64) -> Podcast? {
    return podcasts.first { (podcast) -> Bool in
      podcast.id == id
    }
  }
  
  func reload(podcast: Podcast) {
    guard let dbQueue = self.dbQueue else { return }
    
    let newEpisodes = podcast.fetch()
    if podcast.invokeSave(dbQueue: dbQueue) && podcast.saveEpisodes(dbQueue: dbQueue) {
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: Events.Reloaded.notification, object: nil, userInfo: ["podcastId": podcast.id ?? 0])
        self.detectedNewEpisodes(podcast: podcast, episodes: newEpisodes)
      }
    }
    
  }
  
  func save(episode: Episode) {
    do {
      try dbQueue?.inDatabase { db in
        try episode.save(db)
      }
      
      NotificationCenter.default.post(name: Events.PodcastUpdated.notification, object: nil, userInfo: ["podcastId": episode.podcastId ?? 0])
    } catch let error as DatabaseError {
      Library.handleDatabaseError(error)
    } catch {}
  }
  
  func save(podcast: Podcast) {
    do {
      try dbQueue?.inDatabase { db in
        try podcast.save(db)
      }
      
      NotificationCenter.default.post(name: Events.PodcastUpdated.notification, object: nil, userInfo: ["podcastId": podcast.id ?? 0])
    } catch let error as DatabaseError {
      Library.handleDatabaseError(error)
    } catch {}
  }
  
  func download(episode: Episode) {
    print("Downloading: \(String(describing: episode.enclosureUrl))")
  }
}
