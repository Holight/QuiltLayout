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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        dataInit()
        
        let layout = collectionView.collectionViewLayout as! QuiltLayout
        layout.delegate = self
        //layout.direction = .horizontal
        //layout.blockPixels = CGSize(width: 50, height: 50)
        
        collectionView.reloadData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        collectionView.reloadData()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func dataInit() {
        numbers.removeAll()
        numberWidths.removeAll()
        numberHeights.removeAll()
        for num in 0...15 {
            numbers.append(num)
            numberWidths.append(ViewController.randomLength())
            numberHeights.append(ViewController.randomLength())
        }
    }
    
    @IBAction func add(_ sender: Any) {
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        add(indexPath: visibleIndexPaths.first ?? IndexPath(row: 0, section: 0))
    }
    @IBAction func remove(_ sender: Any) {
        if (numbers.count == 0) { return }
        
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        let toRemove = visibleIndexPaths[Int(arc4random()) % visibleIndexPaths.count]
        remove(indexPath: toRemove)
    }
    @IBAction func reload(_ sender: Any) {
        dataInit()
        collectionView.reloadData()
    }
    
    func colorForNumber(num: Int) -> UIColor {
        return UIColor(hue: CGFloat((19 * num) % 255) / 255, saturation: 1, brightness: 1, alpha: 1)
    }
    
    private var isAnimating = false
    
    func add(indexPath: IndexPath) {
        if (indexPath.row > numbers.count) {
            return
        }
        
        if (isAnimating) {
            return
        }
        isAnimating = true
        
        collectionView.performBatchUpdates( {
            let index = indexPath.row
            self.numbers.insert(self.numbers.count, at: index)
            self.numberWidths.insert(ViewController.randomLength(), at: index)
            self.numberHeights.insert(ViewController.randomLength(), at: index)
            self.collectionView.insertItems(at: [indexPath])
        }) { _ in
            self.isAnimating = false
        }
    }
    
    func remove(indexPath: IndexPath) {
        if (numbers.count == 0 || indexPath.row > numbers.count) {
            return
        }
        
        if (isAnimating) { return }
        isAnimating = true
        
        collectionView.performBatchUpdates({
            let index = indexPath.row
            self.numbers.remove(at: index)
            self.numberWidths.remove(at: index)
            self.numberHeights.remove(at: index)
            self.collectionView.deleteItems(at: [indexPath])
        }) { _ in
            self.isAnimating = false
        }
    }
}

extension ViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        remove(indexPath: indexPath)
    }
}

extension ViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return numbers.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        cell.backgroundColor = colorForNumber(num: numbers[indexPath.row])
        
        var label = cell.viewWithTag(5) as? UILabel
        if (label == nil) {
            label = UILabel(frame: CGRect(x: 0, y: 0, width: 30, height: 20))
        }
        label?.tag = 5
        label?.textColor = UIColor.black
        let number = numbers[indexPath.row]
        label?.text = "\(number)"
        label?.backgroundColor = UIColor.clear
        cell.addSubview(label!)
        
        return cell
    }
}

extension ViewController: QuiltLayoutDelegate {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if (indexPath.row >= numbers.count) {
            //NSLog(@"Asking for index paths of non-existant cells!! %ld from %lu cells", (long)indexPath.row, (unsigned long)numbers.count);
        }
        
        let width = numberWidths[indexPath.row]
        let height = numberHeights[indexPath.row]
        return CGSize(width: width, height: height)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
    }    
}

extension ViewController {
    static func randomLength() -> Int {
        
        // always returns a random length between 1 and 3, weighted towards lower numbers.
        var result = Int(arc4random() % 6)
        
        // 3/6 chance of it being 1.
        if (result <= 2) {
            result = 1
        }
        // 1/6 chance of it being 3.
        else if (result == 5) {
            result = 3
        }
        // 2/6 chance of it being 2.
        else {
            result = 2
        }
        
        return result
    }
}
