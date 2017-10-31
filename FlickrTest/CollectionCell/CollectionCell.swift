
import Foundation
import UIKit

class CollectionCell: UICollectionViewCell {
    
    @IBOutlet var imageView: UIImageView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configurate()
    }
    
    func configurate() {
        self.layer.masksToBounds = false
        self.layer.shadowOffset = CGSize(width: 0, height: 2)
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowRadius = 15
        self.layer.shadowOpacity = 0.3
    }
    
    func loadImage(imgString: String) {
        imageView.downloadedFrom(link: imgString)
    }
}
