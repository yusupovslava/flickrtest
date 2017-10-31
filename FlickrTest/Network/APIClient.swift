import Foundation
import Alamofire
import SwiftyJSON

public let client = APIClient()

let APIString = "https://api.flickr.com/services/rest/"
let flickrKey = "b10273b26bb8f5b2f9697a1f95a3c61c"
let flickrSecret = "6ac85b788f76a44b"

open class APIClient {
    
    public let getImageStringsSignal: Signal<[String]> = MkDeadSignal()
    
    func flickrImagesRequest() {
        
        let url = "\(APIString)?method=flickr.photos.getRecent&api_key=\(flickrKey)&format=json&nojsoncallback=1"
        
        Alamofire.request(url, method: .get, encoding: JSONEncoding.default, headers: nil)
            .responseJSON { response in
                
                if let data = response.data
                {
                    var innerJson: JSON = JSON(data)
                    let photos = innerJson["photos"]["photo"]
                    var imageStringArray = [String]()
                    for dict in photos {
                        let farm:String = dict.1["farm"].stringValue
                        let server:String = dict.1["server"].stringValue
                        let photoID:String = dict.1["id"].stringValue

                        let secret:String = dict.1["secret"].stringValue

                        let imageString:String = "https://farm\(farm).staticflickr.com/\(server)/\(photoID)_\(secret)_n.jpg/"
                        imageStringArray.append(imageString)
                    }
                    self.getImageStringsSignal.push(imageStringArray)
                }
        }
    }
}
