//
//  ViewController.swift
//  YoutubePlayerSample
//
//  Created by Aram Moon on 2019/12/05.
//  Copyright © 2019 Aram Moon. All rights reserved.
//

import UIKit
import YoutubePlayerHelper

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startYoutube()

    }
    
    func startYoutube() {
        
        let player = YoutubePlayerView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        player.load(withVideoId: "R05-G79Dcqc")
        self.view.addSubview(player)
        
        
    }
    
}

