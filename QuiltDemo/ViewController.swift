//
//  ViewController.swift
//  QuiltLayout
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var collectionView: UICollectionView!
    var numbers = [Int]()
    var numberWidths = [Int]()
    var numberHeights = [Int]()
    
    var num = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.dataInit()
        
        let layout = self.collectionView.collectionViewLayout as! QuiltLayout
        layout.delegate = self
        //layout.direction = .vertical
        //layout.blockPixels = CGSize(width: 75, height: 75)
        
        self.collectionView.reloadData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.collectionView.reloadData()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func dataInit() {
        self.numbers.removeAll()
        self.numberWidths.removeAll()
        self.numberHeights.removeAll()
        for num in 0...24 {
            self.numbers.append(num)
            self.numberWidths.append(ViewController.randomLength())
            self.numberHeights.append(ViewController.randomLength())
        }
        //num = 15
    }
    
    @IBAction func add(_ sender: Any) {
    }
    @IBAction func remove(_ sender: Any) {
    }
    @IBAction func reload(_ sender: Any) {
        self.dataInit()
        self.collectionView.reloadData()
    }
    
    func colorForNumber(num: Int) -> UIColor {
        return UIColor(hue: CGFloat((19 * num) % 255) / 255, saturation: 1, brightness: 1, alpha: 1)
    }
}

extension ViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
    }
}

extension ViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.numbers.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        cell.backgroundColor = self.colorForNumber(num: self.numbers[indexPath.row])
        
        var label = cell.viewWithTag(5) as? UILabel
        if (label == nil) {
            label = UILabel(frame: CGRect(x: 0, y: 0, width: 30, height: 20))
        }
        label?.tag = 5
        label?.textColor = UIColor.black
        let number = self.numbers[indexPath.row]
        label?.text = "\(number)"
        label?.backgroundColor = UIColor.clear
        cell.addSubview(label!)
        
        return cell
    }
}

extension ViewController: QuiltLayoutDelegate {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if (indexPath.row >= self.numbers.count) {
            //NSLog(@"Asking for index paths of non-existant cells!! %ld from %lu cells", (long)indexPath.row, (unsigned long)self.numbers.count);
        }
        
        let width = self.numberWidths[indexPath.row]
        let height = self.numberHeights[indexPath.row]
        return CGSize(width: width, height: height)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
    }    
}

extension ViewController {
    static func randomLength() -> Int {
        
        // always returns a random length between 1 and 3, weighted towards lower numbers.
        var result = Int(arc4random() % 6);
        
        // 3/6 chance of it being 1.
        if (result <= 2)
        {
            result = 1;
        }
            // 1/6 chance of it being 3.
        else if (result == 5)
        {
            result = 3;
        }
            // 2/6 chance of it being 2.
        else {
            result = 2;
        }
        
        return result;
    }
}
