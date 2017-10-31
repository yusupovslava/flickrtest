
import UIKit

class ViewController: UIViewController {
    
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var loadingButton: UIButton!
    
    fileprivate var imagesStringsArray: [String] = [String]()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupLoadingButton()
        
        client.getImageStringsSignal.unpullingListen { (photoStrings) in
            self.imagesStringsArray = photoStrings
            self.collectionView.reloadData()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

//MARK: Setup
extension ViewController {
    
    fileprivate func setupLoadingButton() {
        loadingButton.layer.cornerRadius = 2
        loadingButton.addTarget(self, action: #selector(loadButtonAction), for: .touchDown)
    }
}

//MARK: Actions
extension ViewController {
    
    @objc fileprivate func loadButtonAction() {
        client.flickrImagesRequest()
    }
}

//MARK: Collection delegate and data source
extension ViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imagesStringsArray.count
    }
   
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageCell",
                                                            for: indexPath) as? CollectionCell else { return UICollectionViewCell() }
        cell.loadImage(imgString: imagesStringsArray[indexPath.row])
        return cell
    }
}

