//
//  PodcastViewController.swift
//  Doughnut
//
//  Created by Chris Dyer on 23/09/2017.
//  Copyright © 2017 Chris Dyer. All rights reserved.
//

import Cocoa

class PodcastViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
  var podcasts = [Podcast]()
  
  @IBOutlet var tableView: NSTableView!
  
  var viewController: ViewController {
    get {
      return parent as! ViewController
    }
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    reloadPodcasts()
  }
  
  func reloadPodcasts() {
    podcasts = Library.global.podcasts
    tableView.reloadData()
  }
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    return podcasts.count
  }
  
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let podcast = podcasts[row]
    let result = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "defaultRow"), owner: self) as! PodcastCellView
    
    result.title.stringValue = podcast.title
    result.author.stringValue = podcast.author ?? ""
    result.imageView?.image = podcast.image
    result.episodeCount.stringValue = "\(podcast.episodes.count) episodes"
    
    return result
  }
  
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    //NotificationCenter.default.post(name: ViewController.Events.PodcastSelected.notification, object: nil, userInfo: ["podcast": podcasts[row]])
    viewController.selectPodcast(podcast: podcasts[row])
    return true
  }
  
  @IBAction func reloadPodcast(_ sender: Any) {
    Library.global.reload(podcast: podcasts[tableView.clickedRow])
  }
  
  @IBAction func copyPodcastURL(_ sender: Any) {
    if let feed = podcasts[tableView.clickedRow].feed {
      NSPasteboard.general.declareTypes([.string], owner: nil)
      NSPasteboard.general.setString(feed, forType: .string)
    }
  }
  
  @IBAction func unsubscribe(_ sender: Any) {
  }
}
