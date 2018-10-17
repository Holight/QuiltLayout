//
//  QuiltLayout.swift
//  QuiltLayout
//

import Foundation
import UIKit

@objc protocol QuiltLayoutDelegate: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets
}

class QuiltLayout: UICollectionViewLayout {
    
    var delegate: QuiltLayoutDelegate?
    
    var blockPixels: CGSize = CGSize(width: 100, height: 100) {
        didSet {
            invalidateLayout()
        }
    }
    
    var direction: UICollectionView.ScrollDirection = .vertical {
        didSet {
            invalidateLayout()
        }
    }
    
    // only use this if you don't have more than 1000ish items.
    // this will give you the correct size from the start and
    // improve scrolling speed, at the cost of time at the beginning
    var prelayoutEverything = false
    
    private var firstOpenSpace = CGPoint()
    private var furthestBlockPoint = CGPoint()
    
    func setFurthestBlockPoint(_ point: CGPoint) {
        self.furthestBlockPoint = CGPoint(x: max(self.furthestBlockPoint.x, point.x), y: max(self.furthestBlockPoint.y, point.y))
    }
    
    // this will be a 2x2 dictionary storing nsindexpaths
    // which indicate the available/filled spaces in our quilt
    var indexPathByPosition = [CGFloat : [CGFloat : IndexPath]]()
    
    // indexed by "section, row" this will serve as the rapid
    // lookup of block position by indexpath.
    var positionByIndexPath = [Int : [Int : CGPoint]]()
    
    // previous layout cache.  this is to prevent choppiness
    // when we scroll to the bottom of the screen - uicollectionview
    // will repeatedly call layoutattributesforelementinrect on
    // each scroll event.  pow!
    var previousLayoutAttributes: [UICollectionViewLayoutAttributes]?
    var previousLayoutRect: CGRect?
    
    // remember the last indexpath placed, as to not
    // relayout the same indexpaths while scrolling
    var lastIndexPathPlaced: IndexPath?
    
    var isVertical: Bool {
        return self.direction == .vertical
    }
    
    override var collectionViewContentSize: CGSize {
        let contentRect = collectionView!.frame.inset(by: collectionView!.contentInset);
        if isVertical {
            return CGSize(width: contentRect.width, height: (furthestBlockPoint.y+1) * blockPixels.height)
        }
        else {
            return CGSize(width: (furthestBlockPoint.x+1) * blockPixels.width, height: contentRect.height)
        }
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard delegate != nil else {
            return nil
        }
        
        guard rect != previousLayoutRect else {
            return previousLayoutAttributes
        }
        
        previousLayoutRect = rect
        
        let unrestrictedDimensionStart = Int(isVertical ? rect.origin.y / blockPixels.height : rect.origin.x / blockPixels.width)
        let unrestrictedDimensionLength = Int((isVertical ? rect.size.height / blockPixels.height : rect.size.width / blockPixels.width) + 1)
        let unrestrictedDimensionEnd = unrestrictedDimensionStart + unrestrictedDimensionLength
        
        self.fillInBlocks(toUnrestricted: prelayoutEverything ? Int.max : unrestrictedDimensionEnd)
        
        // find the indexPaths between those rows
        var attributes = Set<UICollectionViewLayoutAttributes>()
        self.traverseTilesBetweenUnrestrictedDimension(begin: unrestrictedDimensionStart, and: unrestrictedDimensionEnd) { point in
            if let indexPath = self.indexPath(for: point),
                let attribute = self.layoutAttributesForItem(at: indexPath) {
                attributes.insert(attribute)
            }
            return true
        }
        
        previousLayoutAttributes = Array(attributes)
        return previousLayoutAttributes
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let insets = delegate?.collectionView(collectionView!, layout: self, insetForSectionAt: indexPath.item) ?? UIEdgeInsets()
        let itemFrame = frame(for: indexPath)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = itemFrame.inset(by: insets)
        return attributes
    }
    
    func shouldInvalidateLayoutForBoundsChange(newBounds: CGRect) -> Bool {
        return newBounds.size == collectionView!.frame.size
    }
    
    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        
        for item in updateItems {
            if item.updateAction == .insert || item.updateAction == .move {
                fillInBlocks(to: item.indexPathAfterUpdate!)
            }
        }
    }
    
    override func invalidateLayout() {
        super.invalidateLayout()
        
        furthestBlockPoint = CGPoint.zero
        firstOpenSpace = CGPoint.zero
        previousLayoutRect = CGRect.zero
        previousLayoutAttributes = nil
        lastIndexPathPlaced = nil
        indexPathByPosition.removeAll()
        positionByIndexPath.removeAll()
    }
    
    override func prepare() {
        super.prepare()
        
        guard delegate != nil else { return }
        
        let scrollOrigin = collectionView!.contentOffset
        let scrollSize = collectionView!.frame.size
        let scrollFrame = CGRect(origin: scrollOrigin, size: scrollSize)
        
        let unrestrictedRow = isVertical ? Int(scrollFrame.maxY / blockPixels.height) + 1 : Int(scrollFrame.maxX / blockPixels.width) + 1
        fillInBlocks(toUnrestricted: prelayoutEverything ? Int.max : unrestrictedRow)
    }
    
    func fillInBlocks(toUnrestricted endRow: Int) {
        
        let startIndexPath: IndexPath
        if let lastIndexPathPlaced = lastIndexPathPlaced {
            startIndexPath = IndexPath(item: lastIndexPathPlaced.row + 1, section: lastIndexPathPlaced.section)
        } else {
            startIndexPath = IndexPath(row: 0, section: 0)
        }
        
        // we'll have our data structure as if we're planning
        // a vertical layout, then when we assign positions to
        // the items we'll invert the axis
        let numSections = collectionView!.numberOfSections
        for section in startIndexPath.section..<numSections {
            let numRows = collectionView!.numberOfItems(inSection: section)
            for row in startIndexPath.row..<numRows {
                let indexPath = IndexPath(row: row, section: section)
                
                if placeBlock(at: indexPath) {
                    lastIndexPathPlaced = indexPath
                }
                
                // only jump out if we've already filled up every space up till the resticted row
                if (isVertical ? firstOpenSpace.y : firstOpenSpace.x) >= CGFloat(endRow) {
                    return
                }
            }
        }
    }
    
    func fillInBlocks(to path: IndexPath) {
        let startIndexPath: IndexPath
        if let lastIndexPathPlaced = lastIndexPathPlaced {
            startIndexPath = IndexPath(item: lastIndexPathPlaced.row + 1, section: lastIndexPathPlaced.section)
        } else {
            startIndexPath = IndexPath(row: 0, section: 0)
        }
        
        // we'll have our data structure as if we're planning
        // a vertical layout, then when we assign positions to
        // the items we'll invert the axis
        let numSections = collectionView!.numberOfSections
        for section in startIndexPath.section..<numSections {
            let numRows = collectionView!.numberOfItems(inSection: section)
            for row in startIndexPath.row..<numRows {
                
                // exit when we are past the desired row
                if section >= path.section && row > path.row {
                    return
                }
                
                let indexPath = IndexPath(row: row, section: section)
                if placeBlock(at: indexPath) {
                    lastIndexPathPlaced = indexPath
                }
            }
        }
    }
    
    func placeBlock(at indexPath: IndexPath) -> Bool {
        let blockSize = getBlockSizeForItem(at: indexPath)
        return !traverseOpenTiles() { blockOrigin in
            
            // we need to make sure each square in the desired
            // area is available before we can place the square
            let didTraverseAllBlocks = self.traverseTiles(point: blockOrigin, with: blockSize) { point in
                let spaceAvailable = self.indexPath(for: point) == nil
                let inBounds = (self.isVertical ? point.x : point.y) < CGFloat(self.restrictedDimensionBlockSize)
                let maximumRestrictedBoundSize = (isVertical ? blockOrigin.x : blockOrigin.y) == 0
                
                if spaceAvailable && maximumRestrictedBoundSize && !inBounds {
                    print("\(type(of: self)): layout is not \(self.isVertical ? "wide" : "tall") enough for this piece size: \(blockSize)! Adding anyway...")
                    return true
                }
                
                return spaceAvailable && inBounds
            }
            
            if !didTraverseAllBlocks {
                return true
            }
            
            // because we have determined that the space is all
            // available, lets fill it in as taken.
            self.setIndexPath(indexPath, for: blockOrigin)
            
            self.traverseTiles(point: blockOrigin, with: blockSize) { point in
                self.setPosition(point, for: indexPath)
                self.setFurthestBlockPoint(point)
                
                return true
            }
            
            return false
        }
    }
    
    @discardableResult
    func traverseTilesBetweenUnrestrictedDimension(begin: Int, and end: Int, iterator block: (CGPoint) -> Bool) -> Bool {
        // the double ;; is deliberate, the unrestricted dimension should iterate indefinitely
        for unrestrictedDimension in begin..<end {
            for restrictedDimension in 0..<restrictedDimensionBlockSize {
                let point = isVertical ? CGPoint(x: restrictedDimension, y: unrestrictedDimension) : CGPoint(x: unrestrictedDimension, y: restrictedDimension)
                if !block(point) {
                    return false
                }
            }
        }
        
        return true
    }
    
    @discardableResult
    func traverseTiles(point: CGPoint, with size: CGSize, iterator block: (CGPoint) -> Bool) -> Bool {
        for col in Int(point.x)..<Int(point.x + size.width) {
            for row in Int(point.y)..<Int(point.y + size.height) {
                if !block(CGPoint(x: col, y: row)) {
                    return false
                }
            }
        }
        
        return true;
    }
    
    func traverseOpenTiles(block: (CGPoint) -> Bool) -> Bool {
        var allTakenBefore = true
        
        // the while true is deliberate, the unrestricted dimension should iterate indefinitely
        var unrestrictedDimension = isVertical ? firstOpenSpace.y : firstOpenSpace.x
        while true {
            for restrictedDimension in 0..<restrictedDimensionBlockSize {
                let point = CGPoint(x: isVertical ? CGFloat(restrictedDimension) : unrestrictedDimension,
                                    y: isVertical ? unrestrictedDimension : CGFloat(restrictedDimension))
                
                if indexPath(for: point) != nil {
                    continue
                }
                
                if allTakenBefore {
                    firstOpenSpace = point
                    allTakenBefore = false
                }
                
                if !block(point) {
                    return false
                }
            }
            
            unrestrictedDimension += 1
        }
        
        assert(false, "Could find no good place for a block!")
        return true
    }
    
    func indexPath(for point: CGPoint) -> IndexPath? {
        // to avoid creating unbounded nsmutabledictionaries we should
        // have the innerdict be the unrestricted dimension
        let unrestrictedPoint = (isVertical ? point.y : point.x)
        let restrictedPoint = (isVertical ? point.x : point.y)
        
        return indexPathByPosition[restrictedPoint]?[unrestrictedPoint]
    }
    
    func setPosition(_ point: CGPoint, for indexPath: IndexPath) {
        // to avoid creating unbounded nsmutabledictionaries we should
        // have the innerdict be the unrestricted dimension
        
        let unrestrictedPoint = isVertical ? point.y : point.x
        let restrictedPoint = isVertical ? point.x : point.y
        
        if indexPathByPosition[restrictedPoint] == nil {
            indexPathByPosition[restrictedPoint] = [CGFloat : IndexPath]()
        }
        
        indexPathByPosition[restrictedPoint]![unrestrictedPoint] = indexPath
    }
    
    func position(for path: IndexPath) -> CGPoint {
        
        // if item does not have a position, we will make one!
        if positionByIndexPath[path.section]![path.row] == nil {
            fillInBlocks(to: path)
        }
        
        return positionByIndexPath[path.section]![path.row]!
    }
    
    func setIndexPath(_ path: IndexPath, for point: CGPoint) {
        if positionByIndexPath[path.section] == nil {
            positionByIndexPath[path.section] = [Int : CGPoint]()
        }
        
        positionByIndexPath[path.section]![path.row] = point
    }
    
    func frame(for path: IndexPath) -> CGRect {
        let itemPosition = position(for: path)
        let itemSize = getBlockSizeForItem(at: path)
        
        let contentRect = collectionView!.frame.inset(by: collectionView!.contentInset)
        if isVertical {
            let initialPaddingForContraintedDimension = (contentRect.width - CGFloat(restrictedDimensionBlockSize) * blockPixels.width) / 2
            return CGRect(x: itemPosition.x * blockPixels.width + initialPaddingForContraintedDimension,
                          y: itemPosition.y * blockPixels.height,
                          width: itemSize.width * blockPixels.width,
                          height: itemSize.height * blockPixels.height)
        }
        else {
            let initialPaddingForContraintedDimension = (contentRect.height - CGFloat(restrictedDimensionBlockSize) * blockPixels.height) / 2
            return CGRect(x: itemPosition.x * blockPixels.width,
                          y: itemPosition.y * blockPixels.height + initialPaddingForContraintedDimension,
                          width: itemSize.width * blockPixels.width,
                          height: itemSize.height * blockPixels.height)
        }
    }
    
    //This method is prefixed with get because it may return its value indirectly
    func getBlockSizeForItem(at indexPath: IndexPath) -> CGSize {
        let blockSize = delegate?.collectionView(collectionView!, layout: self, sizeForItemAt: indexPath)
        return blockSize ?? CGSize(width: 1, height: 1)
    }
    
    // this will return the maximum width or height the quilt
    // layout can take, depending on we're growing horizontally
    // or vertically
    var restrictedDimensionBlockSize: Int {
        let contentRect = collectionView!.frame.inset(by: collectionView!.contentInset)
        let size = Int(isVertical ? contentRect.width / blockPixels.width : contentRect.height / blockPixels.height)
        
        if (size == 0) {
            print("\(type(of: self)): cannot fit block of size: \(blockPixels) in content rect \(contentRect)!  Defaulting to 1")
            return 1
        }
        
        return size
    }
}
