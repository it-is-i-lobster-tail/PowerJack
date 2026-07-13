//
//  ExerciseSelctionRow.swift
//  PowerJack
//
//  Created by Brendon on 7/7/26.
//

import SwiftUI

struct ExerciseSelctionRow: View {
    let imageName: String
    let selectionName: String
    let selectionDetail: String
    let doubleImage: Bool
    
    
    var body: some View {
        HStack {
            if doubleImage {
                VStack(spacing: 7) {
                    Image(systemName: imageName)
                        .font(.title3)
                        .foregroundStyle(.blue)
                    Image(systemName: imageName)
                        .font(.title3)
                        .foregroundStyle(.blue)
                        
                }
                .padding(.leading, 10)
            } else {
                Image(systemName: imageName)
                    .font(.title)
                    .foregroundStyle(.blue)
                    .padding(.leading, 10)
            }


            VStack(alignment: .leading) {
                Text(selectionName)
                    .font(.title3)
                    .foregroundStyle(.primary)

                Text(selectionDetail)
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }
            .padding(.leading, 12)

            Spacer()
        }
    }
}
