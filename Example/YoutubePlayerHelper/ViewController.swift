//
//  ViewController.swift
//  YoutubePlayerHelper
//
//  Created by NeolabAram on 12/05/2019.
//  Copyright (c) 2019 NeolabAram. All rights reserved.
//

import UIKit
import YoutubePlayerHelper

class ViewController: UIViewController {

    @IBOutlet weak var playerView: YoutubePlayerView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if playerView.load(withVideoId: "3NsEGaCIT38") {
            playerView.playVideo()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

